-- ============================================
-- FreshBox SpA - Esquema MySQL (EP3)
-- Crea las tablas si no existen; no borra ni cambia datos.
-- Lo ejecuta el Job migrar-datos-ep3 (EV3/k8s/03-migrar-datos-job.yaml) en RDS.
-- ============================================

CREATE DATABASE IF NOT EXISTS freshbox;
USE freshbox;

-- Productos: CRUD que atiende EKS (get, create, update, delete).
CREATE TABLE IF NOT EXISTS productos (
    id INT AUTO_INCREMENT PRIMARY KEY,
    nombre VARCHAR(255) NOT NULL,
    descripcion TEXT,
    precio DECIMAL(10,2) NOT NULL,
    stock INT NOT NULL DEFAULT 0,
    categoria VARCHAR(100),
    imagen_url VARCHAR(500),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

-- Ordenes: las registra Lambda Process-Order desde la cola SQS.
CREATE TABLE IF NOT EXISTS ordenes (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_id VARCHAR(100) NOT NULL,
    total DECIMAL(10,2) NOT NULL,
    estado ENUM('pendiente', 'procesado', 'enviado', 'entregado') DEFAULT 'pendiente',
    items JSON,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    processed_at TIMESTAMP NULL,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

-- 2026 - Disenador asignatura: Ignacio A. Pastenet M.
