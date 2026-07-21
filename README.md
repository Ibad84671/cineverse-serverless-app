# 🍿 CineVerse | Serverless Movie Catalog App

CineVerse is a full-stack, event-driven serverless web application built using **AWS Serverless Architecture**. It allows users to explore, add, and review movies in real-time with zero server management overhead.

---

## 🏗️ Architecture & Tech Stack

- **Frontend**: Hosted on **AWS S3** (Static Website Hosting) built with HTML5, CSS3, JavaScript.
- **API Layer**: **AWS API Gateway** (REST API with CORS enabled).
- **Backend / Compute**: **AWS Lambda** (Python 3.x) handling dynamic CRUD business logic.
- **Database**: **AWS DynamoDB** (NoSQL) for storing movie metadata and reviews.

---

## ✨ Key Features

- 🎬 **Dynamic Catalog**: Renders movies live from DynamoDB.
- ➕ **Add Movies**: Easy input form to add movie entries instantly.
- 💬 **User Remarks**: Feature to post and update custom movie reviews.
- 🗑️ **Admin Control**: Backend moderation capabilities for item deletion via API.

---

## 🚀 API Endpoints

| Method | Endpoint | Description |
| :--- | :--- | :--- |
| `GET` | `/movies` | Fetches all cataloged movies |
| `POST` | `/movies` | Adds a new movie entry |
| `POST` | `/movies` | Updates reviews (`action: update_remark`) |
| `POST` | `/movies` | Deletes a movie (`action: delete_movie`) |

---

## 🛡️ License

Distributed under the MIT License.
