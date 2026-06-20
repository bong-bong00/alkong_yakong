import requests

data = {
    "user_id": "test_user",
    "message": "타이레돌 부작용이 뭐야?"
}

resp = requests.post("http://localhost:8000/api/v1/drug-explain/chat", json=data)
print(resp.status_code)
print(resp.text)
