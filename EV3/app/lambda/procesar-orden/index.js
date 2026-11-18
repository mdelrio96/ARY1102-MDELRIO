// FreshBox - Lambda Process-Order (EP3) - Consumer SQS → MySQL
const mysql = require('mysql2/promise');
const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const { DynamoDBDocumentClient, QueryCommand, BatchWriteCommand } = require('@aws-sdk/lib-dynamodb');
const dynamoClient = new DynamoDBClient({});
const docClient = DynamoDBDocumentClient.from(dynamoClient);
const TABLE_NAME = process.env.TABLE_NAME || 'carrito-freshbox';
const dbConfig = { host: process.env.DB_HOST, user: process.env.DB_USER || 'alumno', password: process.env.DB_PASS || 'alumno123', database: process.env.DB_NAME || 'freshbox', port: parseInt(process.env.DB_PORT) || 3306 };

exports.handler = async (event) => {
    for (const record of event.Records) {
        try {
            const order = JSON.parse(record.body);
            const connection = await mysql.createConnection(dbConfig);
            await connection.execute('INSERT INTO ordenes (user_id, total, estado, items, processed_at) VALUES (?, ?, ?, ?, NOW())', [order.userId, order.total, 'procesado', JSON.stringify(order.items)]);
            await connection.end();
            // Limpiar carrito
            const cartItems = await docClient.send(new QueryCommand({ TableName: TABLE_NAME, KeyConditionExpression: 'userId = :uid', ExpressionAttributeValues: { ':uid': order.userId } }));
            if (cartItems.Items && cartItems.Items.length > 0) {
                const delReqs = cartItems.Items.map(item => ({ DeleteRequest: { Key: { userId: item.userId, productId: item.productId } } }));
                for (let i = 0; i < delReqs.length; i += 25) {
                    await docClient.send(new BatchWriteCommand({ RequestItems: { [TABLE_NAME]: delReqs.slice(i, i + 25) } }));
                }
            }
            console.log(`Orden ${order.orderId} procesada`);
        } catch (error) { console.error('Error:', error.message); throw error; }
    }
    return { statusCode: 200, body: 'OK' };
};

// 2026 - Disenador asignatura: Ignacio A. Pastenet M.
