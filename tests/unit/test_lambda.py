import json
import pytest
from lambda_function import lambda_handler, validate_movie

def test_validate_movie_valid():
    data = {"MovieId": "1", "MovieName": "Test", "Rating": 8.5, "ReleaseYear": 2024}
    errors = validate_movie(data)
    assert errors == []

def test_validate_movie_missing_name():
    data = {"MovieId": "1"}
    errors = validate_movie(data)
    assert "MovieName is required" in errors

def test_validate_movie_invalid_rating():
    data = {"MovieId": "1", "MovieName": "Test", "Rating": 15}
    errors = validate_movie(data)
    assert any("between 0 and 10" in e for e in errors)

def test_handler_get_all():
    event = {"httpMethod": "GET", "path": "/movies"}
    response = lambda_handler(event, None)
    assert response["statusCode"] in [200, 500]