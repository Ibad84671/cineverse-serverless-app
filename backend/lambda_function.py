import base64
import json
import logging
import math
import os
import uuid
from datetime import datetime, timezone

import boto3
from boto3.dynamodb.conditions import Key
from botocore.exceptions import ClientError

logger = logging.getLogger()
logger.setLevel(logging.INFO)

TABLE_NAME = os.environ.get("MOVIE_TABLE_NAME", "MovieCatalog")
LIBRARY_TABLE_NAME = os.environ.get("LIBRARY_TABLE_NAME", "CineVerseUserLibrary")
ALLOWED_ORIGIN = os.environ.get("ALLOWED_ORIGIN", "*")
dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table(TABLE_NAME)
library_table = dynamodb.Table(LIBRARY_TABLE_NAME)

MOVIE_FIELDS = {"MovieName", "Genre", "Language", "Rating", "ReleaseYear", "Director", "Remark", "PosterUrl", "BackdropUrl", "Overview", "Runtime"}
ALLOWED_UPDATE_FIELDS = MOVIE_FIELDS.copy()


def response(status_code, body):
    return {"statusCode": status_code, "headers": {"Content-Type": "application/json", "Access-Control-Allow-Origin": ALLOWED_ORIGIN, "Access-Control-Allow-Headers": "Content-Type,Authorization", "Access-Control-Allow-Methods": "GET,POST,PUT,DELETE,OPTIONS", "Cache-Control": "no-store"}, "body": json.dumps(body, default=str)}


def _claims(event):
    return event.get("requestContext", {}).get("authorizer", {}).get("claims", {}) or {}


def get_authenticated_user(event):
    return _claims(event).get("sub")


def is_admin(event):
    groups = _claims(event).get("cognito:groups", "")
    if isinstance(groups, str):
        groups = {g.strip() for g in groups.split(",") if g.strip()}
    return "admins" in set(groups or [])


def validate_movie(data, is_update=False):
    if not isinstance(data, dict):
        return ["Invalid request body"]
    errors = []
    if not is_update:
        if "MovieName" not in data:
            errors.append("MovieName is required")
        elif not isinstance(data["MovieName"], str):
            errors.append("MovieName must be a string")
        elif not data["MovieName"].strip():
            errors.append("MovieName cannot be empty")
        elif len(data["MovieName"]) > 200:
            errors.append("MovieName must be between 1 and 200 characters")
    for key, value in data.items():
        if key not in MOVIE_FIELDS:
            errors.append(f"Unsupported field: {key}")
        if key in {"Genre", "Language", "Director", "Remark", "PosterUrl", "BackdropUrl", "Overview"} and not isinstance(value, str):
            errors.append(f"{key} must be a string")
    if "MovieName" in data and isinstance(data["MovieName"], str) and len(data["MovieName"]) > 200:
        errors.append("MovieName must be between 1 and 200 characters")
    if "Rating" in data:
        try:
            rating = float(data["Rating"])
            if not math.isfinite(rating) or rating < 0 or rating > 10:
                errors.append("Rating must be between 0 and 10")
        except (ValueError, TypeError):
            errors.append("Rating must be a number")
    if "ReleaseYear" in data:
        try:
            year = int(data["ReleaseYear"])
            if year < 1900 or year > datetime.now(timezone.utc).year + 2:
                errors.append(f"ReleaseYear must be between 1900 and {datetime.now(timezone.utc).year + 2}")
        except (ValueError, TypeError):
            errors.append("ReleaseYear must be a number")
    return errors


def validate_movie_update(data):
    if not isinstance(data, dict) or not data:
        return ["Request body must contain at least one field"]
    return validate_movie(data, is_update=True)


def encode_next_token(data):
    return base64.urlsafe_b64encode(json.dumps(data).encode()).decode().rstrip("=")


def decode_next_token(token):
    try:
        return json.loads(base64.urlsafe_b64decode(token + "===").decode())
    except (ValueError, TypeError, json.JSONDecodeError):
        return None


def _parse_body(event):
    try:
        return json.loads(event.get("body") or "{}")
    except json.JSONDecodeError:
        return None


def handle_get(event):
    movie_id = (event.get("pathParameters") or {}).get("movie_id")
    try:
        if movie_id:
            item = table.get_item(Key={"MovieId": movie_id}).get("Item")
            return response(200, {"success": True, "data": item}) if item else response(404, {"success": False, "error": "Movie not found"})
        query = event.get("queryStringParameters") or {}
        try:
            limit = min(max(int(query.get("limit", 24)), 1), 100)
        except (TypeError, ValueError):
            return response(400, {"success": False, "error": "Invalid limit"})
        params = {"Limit": limit}
        if query.get("nextToken"):
            key = decode_next_token(query["nextToken"])
            if not key:
                return response(400, {"success": False, "error": "Invalid pagination token"})
            params["ExclusiveStartKey"] = key
        result = table.scan(**params)
        data = {"success": True, "data": result.get("Items", []), "movies": result.get("Items", []), "count": len(result.get("Items", []))}
        if result.get("LastEvaluatedKey"):
            data["nextToken"] = encode_next_token(result["LastEvaluatedKey"])
        return response(200, data)
    except ClientError:
        logger.exception("DynamoDB read failed")
        return response(500, {"success": False, "error": "Unable to load movies"})


def handle_post(event):
    user_id = get_authenticated_user(event)
    if not user_id:
        return response(401, {"success": False, "error": "Authentication required"})
    body = _parse_body(event)
    if body is None:
        return response(400, {"success": False, "error": "Invalid JSON"})
    errors = validate_movie(body)
    if errors:
        return response(400, {"success": False, "error": "Validation failed", "details": errors})
    now = datetime.now(timezone.utc).isoformat()
    item = {"MovieId": str(uuid.uuid4()), "MovieName": body["MovieName"].strip(), "createdBy": user_id, "createdAt": now, "updatedAt": now}
    for key in MOVIE_FIELDS - {"MovieName"}:
        if key in body:
            item[key] = body[key]
    try:
        table.put_item(Item=item, ConditionExpression="attribute_not_exists(MovieId)")
        logger.info("Created movie id=%s user=%s", item["MovieId"], user_id)
        return response(201, {"success": True, "data": item, "movieId": item["MovieId"]})
    except ClientError:
        logger.exception("DynamoDB create failed")
        return response(500, {"success": False, "error": "Unable to create movie"})


def handle_put(event):
    user_id = get_authenticated_user(event)
    if not user_id:
        return response(401, {"success": False, "error": "Authentication required"})
    movie_id = (event.get("pathParameters") or {}).get("movie_id")
    if not movie_id:
        return response(400, {"success": False, "error": "movie_id required"})
    try:
        existing = table.get_item(Key={"MovieId": movie_id}).get("Item")
    except ClientError:
        logger.exception("Ownership lookup failed")
        return response(500, {"success": False, "error": "Unable to update movie"})
    if not existing:
        return response(404, {"success": False, "error": "Movie not found"})
    if existing.get("createdBy") != user_id and not is_admin(event):
        return response(403, {"success": False, "error": "You can only edit your own movies"})
    body = _parse_body(event)
    if body is None:
        return response(400, {"success": False, "error": "Invalid JSON"})
    errors = validate_movie_update(body)
    if errors:
        return response(400, {"success": False, "error": "Validation failed", "details": errors})
    names, values = {}, {":updatedAt": datetime.now(timezone.utc).isoformat()}
    parts = ["updatedAt = :updatedAt"]
    for key, value in body.items():
        names[f"#{key}"] = key
        values[f":{key}"] = value
        parts.append(f"#{key} = :{key}")
    try:
        result = table.update_item(Key={"MovieId": movie_id}, UpdateExpression="SET " + ", ".join(parts), ExpressionAttributeNames=names, ExpressionAttributeValues=values, ConditionExpression="attribute_exists(MovieId)", ReturnValues="ALL_NEW")
        return response(200, {"success": True, "data": result["Attributes"]})
    except ClientError:
        logger.exception("DynamoDB update failed")
        return response(500, {"success": False, "error": "Unable to update movie"})


def handle_delete(event):
    user_id = get_authenticated_user(event)
    if not user_id:
        return response(401, {"success": False, "error": "Authentication required"})
    if not is_admin(event):
        return response(403, {"success": False, "error": "Admin access required"})
    movie_id = (event.get("pathParameters") or {}).get("movie_id")
    if not movie_id:
        return response(400, {"success": False, "error": "movie_id required"})
    try:
        result = table.delete_item(Key={"MovieId": movie_id}, ReturnValues="ALL_OLD")
        return response(200, {"success": True, "message": "Movie deleted"}) if result.get("Attributes") else response(404, {"success": False, "error": "Movie not found"})
    except ClientError:
        logger.exception("DynamoDB delete failed")
        return response(500, {"success": False, "error": "Unable to delete movie"})


def handle_watchlist(event):
    user_id = get_authenticated_user(event)
    if not user_id:
        return response(401, {"success": False, "error": "Authentication required"})
    movie_id = (event.get("pathParameters") or {}).get("movie_id")
    try:
        if event.get("httpMethod") == "GET":
            items = library_table.query(KeyConditionExpression=Key("UserId").eq(user_id)).get("Items", [])
            return response(200, {"success": True, "data": items})
        if not movie_id:
            return response(400, {"success": False, "error": "movie_id required"})
        if event.get("httpMethod") == "PUT":
            movie = table.get_item(Key={"MovieId": movie_id}).get("Item")
            if not movie:
                return response(404, {"success": False, "error": "Movie not found"})
            library_table.put_item(Item={"UserId": user_id, "MovieId": movie_id, "MovieName": movie.get("MovieName", ""), "Genre": movie.get("Genre", ""), "Rating": movie.get("Rating", 0), "addedAt": datetime.now(timezone.utc).isoformat()})
            return response(200, {"success": True, "message": "Added to watchlist"})
        if event.get("httpMethod") == "DELETE":
            library_table.delete_item(Key={"UserId": user_id, "MovieId": movie_id})
            return response(200, {"success": True, "message": "Removed from watchlist"})
        return response(405, {"success": False, "error": "Method not allowed"})
    except ClientError:
        logger.exception("Watchlist operation failed")
        return response(500, {"success": False, "error": "Unable to update watchlist"})


def lambda_handler(event, context):
    method = event.get("httpMethod")
    path = event.get("path", "")
    logger.info("request method=%s path=%s requestId=%s", method, path, getattr(context, "aws_request_id", "-"))
    try:
        if method == "OPTIONS":
            return response(204, {})
        if "/watchlist" in path:
            return handle_watchlist(event)
        if method == "GET":
            return handle_get(event)
        if method == "POST":
            return handle_post(event)
        if method == "PUT":
            return handle_put(event)
        if method == "DELETE":
            return handle_delete(event)
        return response(405, {"success": False, "error": f"Method {method} not allowed"})
    except Exception:
        logger.exception("Unhandled request failure")
        return response(500, {"success": False, "error": "Internal server error", "requestId": getattr(context, "aws_request_id", "-")})
