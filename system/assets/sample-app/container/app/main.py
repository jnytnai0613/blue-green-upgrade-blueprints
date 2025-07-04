from fastapi import FastAPI
import boto3

app = FastAPI()

@app.get("/")
def read_root():
    dynamodb = boto3.client("dynamodb", region_name="ap-northeast-1")
    response = dynamodb.scan(
        TableName="test-dynamodb",
    )
    return response["Items"]