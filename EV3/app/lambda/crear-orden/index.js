// FreshBox - Lambda Create-Order (EP3)
const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const { DynamoDBDocumentClient, QueryCommand } = require('@aws-sdk/lib-dynamodb');
const { SQSClient, SendMessageCommand } = require('@aws-sdk/client-sqs');
const dynamoClient = new DynamoDBClient({});
const docClient = DynamoDBDocumentClient.from(dynamoClient);
const sqsClient = new SQSClient({});
const TABLE_NAME = process.env.TABLE_NAME || 'carrito-freshbox';
const QUEUE_URL = process.env.QUEUE_URL;

exports.handler = async (event) => {
    try {
        const { userId } = JSON.parse(event.body);
        if (!userId) return resp(400, { error: 'Campo obligatorio: userId' });
        const cartResult = await docClient.send(new QueryCommand({ TableName: TABLE_NAME, KeyConditionExpression: 'userId = :uid', ExpressionAttributeValues: { ':uid': userId } }));
        const items = cartResult.Items || [];
        if (items.length === 0) return resp(400, { error: 'Carrito vacio', userId });
        const total = items.reduce((sum, item) => sum + (item.precio * item.cantidad), 0);
        const orderId = `ORD-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;
        await sqsClient.send(new SendMessageCommand({ QueueUrl: QUEUE_URL, MessageBody: JSON.stringify({ orderId, userId, items: items.map(i => ({ productId: i.productId, nombre: i.nombre, precio: i.precio, cantidad: i.cantidad })), total, createdAt: new Date().toISOString() }) }));
        return resp(200, { message: 'Su pedido fue recibido', orderId, total, cantidadItems: items.length, estado: 'pendiente' });
    } catch (error) { return resp(500, { error: 'Error al crear orden', detalle: error.message }); }
};

function resp(statusCode, body) { return { statusCode, headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Methods': 'POST,OPTIONS', 'Access-Control-Allow-Headers': 'Content-Type' }, body: JSON.stringify(body) }; }

// 2026 - Disenador asignatura: Ignacio A. Pastenet M.
