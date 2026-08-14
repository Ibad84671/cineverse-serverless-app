import json
import os
import uuid
import logging
from datetime import datetime
import boto3
from boto3.dynamodb.conditions import Key
from botocore.exceptions import ClientError

# ─── LOGGING ──────────────────────────────────────────────────────────────
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# ─── CONFIG ──────────────────────────────────────────────────────────────
TABLE_NAME = os.environ.get("MOVIE_TABLE_NAME", "MovieCatalog")
ALLOWED_ORIGIN = os.environ.get("ALLOWED_ORIGIN", "*")
REGION = os.environ.get("AWS_REGION", "us-east-1")

dynamodb = boto3.resource("dynamodb", region_name=REGION)
table = dynamodb.Table(TABLE_NAME)

# ─── HELPERS ─────────────────────────────────────────────────────────────
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

def validate_movie(data):
    """Validate movie data before storing."""
    errors = []
    
    # MovieId is required
    if "MovieId" not in data:
        errors.append("MovieId is required")
    
    # MovieName is required
    if "MovieName" not in data:
        errors.append("MovieName is required")
    elif len(data["MovieName"]) > 200:
        errors.append("MovieName too long (max 200)")
    
    # Rating validation
    if "Rating" in data:
        try:
            rating = float(data["Rating"])
            if rating < 0 or rating > 10:
                errors.append("Rating must be between 0 and 10")
        except (ValueError, TypeError):
            errors.append("Rating must be a number")
    
    # ReleaseYear validation
    if "ReleaseYear" in data:
        try:
            year = int(data["ReleaseYear"])
            if year < 1900 or year > datetime.now().year + 1:
                errors.append(f"ReleaseYear must be between 1900 and {datetime.now().year + 1}")
        except (ValueError, TypeError):
            errors.append("ReleaseYear must be a number")
    
    return errors

# ─── API HANDLERS ──────────────────────────────────────────────────────
def handle_get(event):
    """GET /movies or GET /movies/{id}"""
    path_params = event.get("pathParameters")
    
    if path_params and path_params.get("movie_id"):
        # Get single movie
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
    
    # Get all movies (with pagination)
    try:
        # Use Query if you have a GSI, otherwise Scan (small dataset)
        # For demo, Scan is acceptable, but we add pagination
        params = {}
        if event.get("queryStringParameters"):
            limit = event["queryStringParameters"].get("limit")
            if limit:
                params["Limit"] = int(limit)
        
        result = table.scan(**params)
        items = result.get("Items", [])
        
        # Build response with pagination token
        resp = {"movies": items, "count": len(items)}
        if "LastEvaluatedKey" in result:
            resp["nextToken"] = result["LastEvaluatedKey"]
        
        return response(200, resp)
    except ClientError as e:
        logger.error(f"DynamoDB error: {e}")
        return response(500, {"error": "Database error"})

def handle_post(event):
    """POST /movies – create a new movie"""
    try:
        body = json.loads(event.get("body", "{}"))
    except json.JSONDecodeError:
        return response(400, {"error": "Invalid JSON"})
    
    # Validate
    validation_errors = validate_movie(body)
    if validation_errors:
        return response(400, {"error": "Validation failed", "details": validation_errors})
    
    # Ensure MovieId is provided (or generate if missing)
    if "MovieId" not in body:
        body["MovieId"] = str(uuid.uuid4())
    
    try:
        table.put_item(Item=body)
        logger.info(f"Created movie: {body.get('MovieId')}")
        return response(201, {"message": "Movie created", "movie": body})
    except ClientError as e:
        logger.error(f"DynamoDB error: {e}")
        return response(500, {"error": "Database error"})

def handle_put(event):
    """PUT /movies/{id} – update a movie"""
    path_params = event.get("pathParameters")
    if not path_params or not path_params.get("movie_id"):
        return response(400, {"error": "movie_id required"})
    
    movie_id = path_params["movie_id"]
    
    try:
        body = json.loads(event.get("body", "{}"))
    except json.JSONDecodeError:
        return response(400, {"error": "Invalid JSON"})
    
    # Remove MovieId from body if present (we use path param)
    body.pop("MovieId", None)
    
    # Build update expression
    update_parts = []
    expr_values = {}
    expr_names = {}
    
    for key, value in body.items():
        field = f"#{key}"
        val = f":{key}"
        update_parts.append(f"{field} = {val}")
        expr_values[val] = value
        expr_names[field] = key
    
    if not update_parts:
        return response(400, {"error": "No fields to update"})
    
    update_expr = "SET " + ", ".join(update_parts)
    
    try:
        result = table.update_item(
            Key={"MovieId": movie_id},
            UpdateExpression=update_expr,
            ExpressionAttributeNames=expr_names,
            ExpressionAttributeValues=expr_values,
            ReturnValues="ALL_NEW"
        )
        logger.info(f"Updated movie: {movie_id}")
        return response(200, {"message": "Movie updated", "movie": result.get("Attributes")})
    except ClientError as e:
        logger.error(f"DynamoDB error: {e}")
        return response(500, {"error": "Database error"})

def handle_delete(event):
    """DELETE /movies/{id} – delete a movie"""
    path_params = event.get("pathParameters")
    if not path_params or not path_params.get("movie_id"):
        return response(400, {"error": "movie_id required"})
    
    movie_id = path_params["movie_id"]
    
    try:
        table.delete_item(Key={"MovieId": movie_id})
        logger.info(f"Deleted movie: {movie_id}")
        return response(200, {"message": f"Movie {movie_id} deleted"})
    except ClientError as e:
        logger.error(f"DynamoDB error: {e}")
        return response(500, {"error": "Database error"})

def handle_options():
    """OPTIONS – CORS preflight"""
    return response(200, {})

# ─── MAIN HANDLER ──────────────────────────────────────────────────────
def lambda_handler(event, context):
    logger.info(f"Method: {event.get('httpMethod')}, Path: {event.get('path')}")
    
    http_method = event.get("httpMethod")
    
    try:
        if http_method == "OPTIONS":
            return handle_options()
        elif http_method == "GET":
            return handle_get(event)
        elif http_method == "POST":
            return handle_post(event)
        elif http_method == "PUT":
            return handle_put(event)
        elif http_method == "DELETE":
            return handle_delete(event)
        else:
            return response(405, {"error": f"Method {http_method} not allowed"})
    except Exception as e:
        logger.error(f"Unhandled error: {e}", exc_info=True)
        return response(500, {"error": "Internal server error", "requestId": context.aws_request_id})