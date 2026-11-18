-- ============================================
-- FreshBox SpA - Productos iniciales (EP3)
-- Solo se carga si la tabla productos esta vacia (lo decide el Job migrar-datos-ep3).
-- Son los mismos productos de la base de EP1 (EV1/app/init.sql).
-- ============================================

USE freshbox;

INSERT INTO productos (nombre, descripcion, precio, stock, categoria) VALUES
('Manzana organica 1kg', 'Manzanas rojas organicas, cultivo sin pesticidas, bolsa 1 kilogramo', 3490.00, 120, 'Frutas'),
('Lechuga hidroponica', 'Lechuga fresca cultivada en sistema hidroponico, libre de tierra', 1990.00, 80, 'Verduras'),
('Granola artesanal 500g', 'Granola con avena, miel, almendras y arandanos, sin azucar refinada', 4990.00, 60, 'Snacks'),
('Jugo natural naranja 1L', 'Jugo 100% natural de naranja, sin preservantes ni colorantes', 2990.00, 100, 'Bebidas'),
('Mix frutos secos 250g', 'Mezcla de almendras, nueces, castanas de caju y pasas organicas', 5490.00, 45, 'Snacks');

-- 2026 - Disenador asignatura: Ignacio A. Pastenet M.
