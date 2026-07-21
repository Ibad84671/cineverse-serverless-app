import json
import boto3
from decimal import Decimal

dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table('MovieCatalog')

# Decimal to float converter for JSON serialization
class DecimalEncoder(json.JSONEncoder):
    def default(self, obj):
        if isinstance(obj, Decimal):
            return float(obj)
        return super(DecimalEncoder, self).default(obj)

def lambda_handler(event, context):
    cors_headers = {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token',
        'Access-Control-Allow-Methods': 'GET,POST,PUT,DELETE,OPTIONS'
    }

    http_method = event.get('httpMethod', 'GET')

    try:
        # Handling CORS Preflight
        if http_method == 'OPTIONS':
            return {
                'statusCode': 200,
                'headers': cors_headers,
                'body': json.dumps('CORS OK')
            }

        # GET: Fetch All Movies
        if http_method == 'GET':
            response = table.scan()
            items = response.get('Items', [])
            return {
                'statusCode': 200,
                'headers': cors_headers,
                'body': json.dumps(items, cls=DecimalEncoder)
            }

        # POST: Add New Movie OR Update Remark
        if http_method == 'POST':
            body = json.loads(event.get('body', '{}'), parse_float=Decimal)
            
            # Action check for Remark Update
            if body.get('action') == 'update_remark':
                movie_id = body.get('MovieId')
                remark = body.get('remark')
                
                get_res = table.get_item(Key={'MovieId': movie_id})
                if 'Item' in get_res:
                    item = get_res['Item']
                    item['remark'] = remark
                    table.put_item(Item=item)
                    return {
                        'statusCode': 200,
                        'headers': cors_headers,
                        'body': json.dumps({'message': 'Remark updated successfully'})
                    }
                else:
                    return {
                        'statusCode': 404,
                        'headers': cors_headers,
                        'body': json.dumps({'error': 'Movie not found'})
                    }

            # Normal Add Movie
            table.put_item(Item=body)
            return {
                'statusCode': 200,
                'headers': cors_headers,
                'body': json.dumps({'message': 'Movie added successfully'})
            }

        return {
            'statusCode': 400,
            'headers': cors_headers,
            'body': json.dumps({'error': 'Unsupported HTTP method'})
        }

    except Exception as e:
        return {
            'statusCode': 500,
            'headers': cors_headers,
            'body': json.dumps({'error': str(e)})
        }
