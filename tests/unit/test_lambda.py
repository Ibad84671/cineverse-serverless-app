import json
import pytest
from unittest.mock import patch, MagicMock
from lambda_function import validate_movie, get_authenticated_user, is_admin

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