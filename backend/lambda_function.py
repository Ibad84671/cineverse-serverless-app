import json
import os
import uuid
import logging
import base64
import math
from datetime import datetime, timezone
import boto3
from boto3.dynamodb.conditions import Key
from botocore.exceptions import ClientError

logger = logging.getLogger()
logger.setLevel(logging.INFO)

TABLE_NAME = os.environ.get("MOVIE_TABLE_NAME", "MovieCatalog")
ALLOWED_ORIGIN = os.environ.get("ALLOWED_ORIGIN", "https://your-cloudfront-url")
REGION = os.environ.get("AWS_REGION", "us-east-1")

dynamodb = boto3.resource("dynamodb", region_name=REGION)
table = dynamodb.Table(TABLE_NAME)

ALLOWED_UPDATE_FIELDS = {
    "MovieName", "Genre", "Language", "Rating", "ReleaseYear", "Director", "Remark"
}

def response(status_code, body):
    return {
        "statusCode": status_code,
        "headers": {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": ALLOWED_ORIGIN,
            "Access-Control-Allow-Headers": "Content-Type,Authorization",
            "Access-Control-Allow-Methods": "GET,POST,PUT,DELETE,OPTIONS"
        },
        "body": json.dumps(body)
    }

def validate_movie(data, is_update=False):
    errors = []
    if not data or not isinstance(data, dict):
        errors.append("Invalid request body")
        return errors

    if not is_update:
        if "MovieName" not in data:
            errors.append("MovieName is required")
        elif not isinstance(data.get("MovieName"), str):
            errors.append("MovieName must be a string")
        elif len(data.get("MovieName", "")) > 200:
            errors.append("MovieName must be between 1 and 200 characters")
        elif not data.get("MovieName", "").strip():
            errors.append("MovieName cannot be empty")

    if "Rating" in data:
        try:
            rating = float(data["Rating"])
            if math.isnan(rating):
                errors.append("Rating must be a number")
            elif rating < 0 or rating > 10:
                errors.append("Rating must be between 0 and 10")
        except (ValueError, TypeError):
            errors.append("Rating must be a number")

    if "ReleaseYear" in data:
        try:
            year = int(data["ReleaseYear"])
            if year < 1900 or year > datetime.now(timezone.utc).year + 1:
                errors.append(f"ReleaseYear must be between 1900 and {datetime.now(timezone.utc).year + 1}")
        except (ValueError, TypeError):
            errors.append("ReleaseYear must be a number")

    for field in ["Genre", "Language", "Director", "Remark"]:
        if field in data and not isinstance(data[field], str):
            errors.append(f"{field} must be a string")

    return errors

def validate_movie_update(data):
    errors = []
    if not isinstance(data, dict) or not data:
        errors.append("Request body must contain at least one field")
        return errors

    unknown = set(data.keys()) - ALLOWED_UPDATE_FIELDS
    if unknown:
        errors.append(f"Unsupported fields: {', '.join(sorted(unknown))}")

    if "MovieName" in data:
        if not isinstance(data["MovieName"], str):
            errors.append("MovieName must be a string")
        elif len(data["MovieName"]) > 200:
            errors.append("MovieName must be between 1 and 200 characters")

    if "Rating" in data:
        try:
            rating = float(data["Rating"])
            if math.isnan(rating):
                errors.append("Rating must be a number")
            elif rating < 0 or rating > 10:
                errors.append("Rating must be between 0 and 10")
        except (ValueError, TypeError):
            errors.append("Rating must be a number")

    if "ReleaseYear" in data:
        try:
            year = int(data["ReleaseYear"])
            if year < 1900 or year > datetime.now(timezone.utc).year + 1:
                errors.append(f"ReleaseYear must be between 1900 and {datetime.now(timezone.utc).year + 1}")
        except (ValueError, TypeError):
            errors.append("ReleaseYear must be a number")

    for field in ["Genre", "Language", "Director", "Remark"]:
        if field in data and not isinstance(data[field], str):
            errors.append(f"{field} must be a string")

    return errors

def get_authenticated_user(event):
    claims = event.get("requestContext", {}).get("authorizer", {}).get("claims", {})
    return claims.get("sub")

def is_admin(event):
    claims = event.get("requestContext", {}).get("authorizer", {}).get("claims", {})
    groups = claims.get("cognito:groups", "")
    if isinstance(groups, str):
        groups = {g.strip() for g in groups.split(",") if g.strip()}
    return "admins" in groups

def decode_next_token(token):
    try:
        decoded = base64.urlsafe_b64decode(token + "==")
        return json.loads(decoded.decode('utf-8'))
    except Exception:
        return None

def encode_next_token(data):
    encoded = json.dumps(data).encode('utf-8')
    return base64.urlsafe_b64encode(encoded).decode('utf-8').rstrip("=")

def handle_get(event):
    path_params = event.get("pathParameters")
    if path_params and path_params.get("movie_id"):
        movie_id = path_params["movie_id"]
        try:
            result = table.get_item(Key={"MovieId": movie_id})
            item = result.get("Item")
            if not item:
                return response(404, {"error": "Movie not found"})
            return response(200, item)
        except ClientError as e:
            logger.error(f"DynamoDB error: {e}")
            return response(500, {"error": "Database error"})

    try:
        params = {}
        query_params = event.get("queryStringParameters") or {}

        if "limit" in query_params:
            try:
                params["Limit"] = int(query_params["limit"])
                if params["Limit"] > 100:
                    return response(400, {"error": "Limit cannot exceed 100"})
            except ValueError:
                return response(400, {"error": "Invalid limit"})

        if "nextToken" in query_params:
            start_key = decode_next_token(query_params["nextToken"])
            if start_key:
                params["ExclusiveStartKey"] = start_key
            else:
                return response(400, {"error": "Invalid pagination token"})

        result = table.scan(**params)
        items = result.get("Items", [])
        resp = {"movies": items, "count": len(items)}
        if "LastEvaluatedKey" in result:
            resp["nextToken"] = encode_next_token(result["LastEvaluatedKey"])

        return response(200, resp)
    except ClientError as e:
        logger.error(f"DynamoDB error: {e}")
        return response(500, {"error": "Database error"})

def handle_post(event):
    user_id = get_authenticated_user(event)
    if not user_id:
        return response(401, {"error": "Authentication required"})

    try:
        body = json.loads(event.get("body", "{}"))
    except json.JSONDecodeError:
        return response(400, {"error": "Invalid JSON"})

    errors = validate_movie(body, is_update=False)
    if errors:
        return response(400, {"error": "Validation failed", "details": errors})

    movie_id = str(uuid.uuid4())
    now = datetime.now(timezone.utc).isoformat()

    item = {
        "MovieId": movie_id,
        "MovieName": body["MovieName"],
        "Genre": body.get("Genre", ""),
        "Language": body.get("Language", ""),
        "Rating": float(body.get("Rating", 0)),
        "ReleaseYear": int(body.get("ReleaseYear", 0)) if body.get("ReleaseYear") else 0,
        "Director": body.get("Director", ""),
        "Remark": body.get("Remark", ""),
        "createdBy": user_id,
        "createdAt": now,
        "updatedAt": now
    }

    try:
        table.put_item(Item=item)
        logger.info(f"Created movie {movie_id} by user {user_id}")
        return response(201, {"message": "Movie created", "movieId": movie_id})
    except ClientError as e:
        logger.error(f"DynamoDB error: {e}")
        return response(500, {"error": "Database error"})

def handle_put(event):
    user_id = get_authenticated_user(event)
    if not user_id:
        return response(401, {"error": "Authentication required"})

    path_params = event.get("pathParameters")
    if not path_params or not path_params.get("movie_id"):
        return response(400, {"error": "movie_id required"})

    movie_id = path_params["movie_id"]

    try:
        existing = table.get_item(Key={"MovieId": movie_id})
        if "Item" not in existing:
            return response(404, {"error": "Movie not found"})
        owner = existing["Item"].get("createdBy")
        if owner and owner != user_id and not is_admin(event):
            return response(403, {"error": "You can only edit your own movies"})
    except ClientError as e:
        logger.error(f"DynamoDB error checking ownership: {e}")
        return response(500, {"error": "Database error"})

    try:
        body = json.loads(event.get("body", "{}"))
    except json.JSONDecodeError:
        return response(400, {"error": "Invalid JSON"})

    errors = validate_movie_update(body)
    if errors:
        return response(400, {"error": "Validation failed", "details": errors})

    update_parts = []
    expr_values = {":updatedAt": datetime.now(timezone.utc).isoformat()}
    expr_names = {}

    for key, value in body.items():
        field = f"#{key}"
        val = f":{key}"
        update_parts.append(f"{field} = {val}")
        expr_values[val] = value
        expr_names[field] = key

    if not update_parts:
        return response(400, {"error": "No fields to update"})

    update_parts.append("updatedAt = :updatedAt")
    update_expr = "SET " + ", ".join(update_parts)

    try:
        result = table.update_item(
            Key={"MovieId": movie_id},
            UpdateExpression=update_expr,
            ExpressionAttributeNames=expr_names,
            ExpressionAttributeValues=expr_values,
            ConditionExpression="attribute_exists(MovieId)",
            ReturnValues="ALL_NEW"
        )
        logger.info(f"Updated movie {movie_id} by user {user_id}")
        return response(200, {"message": "Movie updated", "movie": result.get("Attributes")})
    except ClientError as e:
        if e.response['Error']['Code'] == 'ConditionalCheckFailedException':
            return response(404, {"error": "Movie not found"})
        logger.error(f"DynamoDB error: {e}")
        return response(500, {"error": "Database error"})

def handle_delete(event):
    user_id = get_authenticated_user(event)
    if not user_id:
        return response(401, {"error": "Authentication required"})

    if not is_admin(event):
        return response(403, {"error": "Admin access required"})

    path_params = event.get("pathParameters")
    if not path_params or not path_params.get("movie_id"):
        return response(400, {"error": "movie_id required"})

    movie_id = path_params["movie_id"]

    try:
        result = table.delete_item(
            Key={"MovieId": movie_id},
            ReturnValues="ALL_OLD"
        )
        if "Attributes" not in result:
            return response(404, {"error": "Movie not found"})
        logger.info(f"Deleted movie {movie_id} by admin {user_id}")
        return response(200, {"message": f"Movie {movie_id} deleted"})
    except ClientError as e:
        logger.error(f"DynamoDB error: {e}")
        return response(500, {"error": "Database error"})

def handle_options():
    return response(200, {})

def lambda_handler(event, context):
    method = event.get("httpMethod")
    logger.info(f"method={method} path={event.get('path')} requestId={context.aws_request_id}")

    try:
        if method == "OPTIONS":
            return handle_options()
        elif method == "GET":
            return handle_get(event)
        elif method == "POST":
            return handle_post(event)
        elif method == "PUT":
            return handle_put(event)
        elif method == "DELETE":
            return handle_delete(event)
        else:
            return response(405, {"error": f"Method {method} not allowed"})
    except Exception as e:
        logger.error(f"Unhandled error: {e}", exc_info=True)
        return response(500, {"error": "Internal server error", "requestId": context.aws_request_id})