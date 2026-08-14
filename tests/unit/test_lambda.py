import json
import pytest
from unittest.mock import patch, MagicMock
from lambda_function import (
    validate_movie,
    validate_movie_update,
    get_authenticated_user,
    is_admin,
    lambda_handler
)

# ─── VALIDATION TESTS ──────────────────────────────────────────────────

def test_validate_movie_valid():
    data = {"MovieName": "Test", "Rating": 8.5, "ReleaseYear": 2024}
    errors = validate_movie(data, is_update=False)
    assert errors == []

def test_validate_movie_missing_name():
    data = {"Rating": 8.5}
    errors = validate_movie(data, is_update=False)
    assert "MovieName is required" in errors

def test_validate_movie_name_too_long():
    data = {"MovieName": "A" * 300}
    errors = validate_movie(data, is_update=False)
    assert any("between 1 and 200" in e for e in errors)

def test_validate_movie_rating_out_of_range():
    data = {"MovieName": "Test", "Rating": 15}
    errors = validate_movie(data, is_update=False)
    assert any("between 0 and 10" in e for e in errors)

def test_validate_movie_rating_nan():
    data = {"MovieName": "Test", "Rating": float('nan')}
    errors = validate_movie(data, is_update=False)
    assert any("number" in e for e in errors)

def test_validate_movie_year_out_of_range():
    data = {"MovieName": "Test", "ReleaseYear": 1800}
    errors = validate_movie(data, is_update=False)
    assert any("between 1900" in e for e in errors)

def test_validate_movie_rating_string():
    data = {"MovieName": "Test", "Rating": "not-a-number"}
    errors = validate_movie(data, is_update=False)
    assert any("number" in e for e in errors)

def test_validate_movie_name_non_string():
    data = {"MovieName": 123}
    errors = validate_movie(data, is_update=False)
    assert any("string" in e for e in errors)

# ─── AUTH TESTS ──────────────────────────────────────────────────────

def test_get_authenticated_user_valid():
    event = {"requestContext": {"authorizer": {"claims": {"sub": "user-123"}}}}
    assert get_authenticated_user(event) == "user-123"

def test_get_authenticated_user_missing():
    assert get_authenticated_user({}) is None

def test_is_admin_true():
    event = {"requestContext": {"authorizer": {"claims": {"cognito:groups": "admins"}}}}
    assert is_admin(event) is True

def test_is_admin_false():
    event = {"requestContext": {"authorizer": {"claims": {"cognito:groups": "users"}}}}
    assert is_admin(event) is False

def test_is_admin_multiple_groups():
    event = {"requestContext": {"authorizer": {"claims": {"cognito:groups": "users,admins,guests"}}}}
    assert is_admin(event) is True

def test_is_admin_empty():
    event = {"requestContext": {"authorizer": {"claims": {}}}}
    assert is_admin(event) is False

# ─── UPDATE VALIDATION TESTS ─────────────────────────────────────────

def test_validate_movie_update_valid():
    data = {"MovieName": "Updated Name", "Rating": 9.0}
    errors = validate_movie_update(data)
    assert errors == []

def test_validate_movie_update_unsupported_field():
    data = {"InvalidField": "value"}
    errors = validate_movie_update(data)
    assert any("Unsupported" in e for e in errors)

def test_validate_movie_update_name_too_long():
    data = {"MovieName": "A" * 300}
    errors = validate_movie_update(data)
    assert any("between 1 and 200" in e for e in errors)

def test_validate_movie_update_rating_out_of_range():
    data = {"Rating": 15}
    errors = validate_movie_update(data)
    assert any("between 0 and 10" in e for e in errors)

# ─── HANDLER TESTS (MOCKED) ──────────────────────────────────────────

@patch('lambda_function.table')
def test_handler_get_success(mock_table):
    mock_table.scan.return_value = {"Items": [{"MovieId": "1", "MovieName": "Test"}]}
    event = {"httpMethod": "GET", "path": "/movies"}
    response = lambda_handler(event, None)
    assert response["statusCode"] == 200

@patch('lambda_function.table')
def test_handler_get_not_found(mock_table):
    mock_table.scan.return_value = {"Items": []}
    event = {"httpMethod": "GET", "path": "/movies"}
    response = lambda_handler(event, None)
    assert response["statusCode"] == 200
    assert "movies" in json.loads(response["body"])

def test_handler_unsupported_method():
    event = {"httpMethod": "PATCH"}
    response = lambda_handler(event, None)
    assert response["statusCode"] == 405
    assert "not allowed" in json.loads(response["body"])["error"]

@patch('lambda_function.table')
def test_handler_get_single_movie_success(mock_table):
    mock_table.get_item.return_value = {"Item": {"MovieId": "1", "MovieName": "Test"}}
    event = {"httpMethod": "GET", "path": "/movies/1", "pathParameters": {"movie_id": "1"}}
    response = lambda_handler(event, None)
    assert response["statusCode"] == 200

@patch('lambda_function.table')
def test_handler_get_single_movie_not_found(mock_table):
    mock_table.get_item.return_value = {}
    event = {"httpMethod": "GET", "path": "/movies/1", "pathParameters": {"movie_id": "1"}}
    response = lambda_handler(event, None)
    assert response["statusCode"] == 404

@patch('lambda_function.table')
@patch('lambda_function.get_authenticated_user')
def test_handler_post_requires_auth(mock_auth, mock_table):
    mock_auth.return_value = None
    event = {"httpMethod": "POST", "body": "{}"}
    response = lambda_handler(event, None)
    assert response["statusCode"] == 401

@patch('lambda_function.table')
@patch('lambda_function.get_authenticated_user')
def test_handler_post_valid(mock_auth, mock_table):
    mock_auth.return_value = "user-123"
    mock_table.put_item.return_value = {}
    event = {
        "httpMethod": "POST",
        "body": json.dumps({"MovieName": "Inception", "Rating": 9.2})
    }
    response = lambda_handler(event, None)
    assert response["statusCode"] == 201

@patch('lambda_function.table')
@patch('lambda_function.get_authenticated_user')
def test_handler_post_invalid(mock_auth, mock_table):
    mock_auth.return_value = "user-123"
    event = {"httpMethod": "POST", "body": "not json"}
    response = lambda_handler(event, None)
    assert response["statusCode"] == 400

@patch('lambda_function.table')
@patch('lambda_function.get_authenticated_user')
def test_handler_put_owner(mock_auth, mock_table):
    mock_auth.return_value = "user-123"
    mock_table.get_item.return_value = {"Item": {"createdBy": "user-123"}}
    mock_table.update_item.return_value = {"Attributes": {}}
    event = {
        "httpMethod": "PUT",
        "pathParameters": {"movie_id": "1"},
        "body": json.dumps({"MovieName": "Updated"})
    }
    response = lambda_handler(event, None)
    assert response["statusCode"] == 200

@patch('lambda_function.table')
@patch('lambda_function.get_authenticated_user')
def test_handler_put_other_user(mock_auth, mock_table):
    mock_auth.return_value = "user-456"
    mock_table.get_item.return_value = {"Item": {"createdBy": "user-123"}}
    event = {
        "httpMethod": "PUT",
        "pathParameters": {"movie_id": "1"},
        "body": json.dumps({"MovieName": "Updated"})
    }
    response = lambda_handler(event, None)
    assert response["statusCode"] == 403

@patch('lambda_function.table')
@patch('lambda_function.get_authenticated_user')
def test_handler_put_admin(mock_auth, mock_table):
    mock_auth.return_value = "user-456"
    mock_table.get_item.return_value = {"Item": {"createdBy": "user-123"}}
    mock_table.update_item.return_value = {"Attributes": {}}
    with patch('lambda_function.is_admin') as mock_admin:
        mock_admin.return_value = True
        event = {
            "httpMethod": "PUT",
            "pathParameters": {"movie_id": "1"},
            "body": json.dumps({"MovieName": "Updated"})
        }
        response = lambda_handler(event, None)
        assert response["statusCode"] == 200

@patch('lambda_function.table')
@patch('lambda_function.get_authenticated_user')
def test_handler_put_missing_movie(mock_auth, mock_table):
    mock_auth.return_value = "user-123"
    mock_table.get_item.return_value = {}
    event = {
        "httpMethod": "PUT",
        "pathParameters": {"movie_id": "1"},
        "body": json.dumps({"MovieName": "Updated"})
    }
    response = lambda_handler(event, None)
    assert response["statusCode"] == 404

@patch('lambda_function.table')
@patch('lambda_function.get_authenticated_user')
def test_handler_delete_admin(mock_auth, mock_table):
    mock_auth.return_value = "user-456"
    mock_table.delete_item.return_value = {"Attributes": {}}
    with patch('lambda_function.is_admin') as mock_admin:
        mock_admin.return_value = True
        event = {
            "httpMethod": "DELETE",
            "pathParameters": {"movie_id": "1"}
        }
        response = lambda_handler(event, None)
        assert response["statusCode"] == 200

@patch('lambda_function.table')
@patch('lambda_function.get_authenticated_user')
def test_handler_delete_non_admin(mock_auth, mock_table):
    mock_auth.return_value = "user-123"
    with patch('lambda_function.is_admin') as mock_admin:
        mock_admin.return_value = False
        event = {
            "httpMethod": "DELETE",
            "pathParameters": {"movie_id": "1"}
        }
        response = lambda_handler(event, None)
        assert response["statusCode"] == 403

@patch('lambda_function.table')
@patch('lambda_function.get_authenticated_user')
def test_handler_delete_missing_movie(mock_auth, mock_table):
    mock_auth.return_value = "user-456"
    mock_table.delete_item.return_value = {}
    with patch('lambda_function.is_admin') as mock_admin:
        mock_admin.return_value = True
        event = {
            "httpMethod": "DELETE",
            "pathParameters": {"movie_id": "1"}
        }
        response = lambda_handler(event, None)
        assert response["statusCode"] == 404