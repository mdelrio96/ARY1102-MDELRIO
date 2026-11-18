// FreshBox SpA - Frontend S3 con Carrito + Ordenes - EP3
const API_URL = "https://<API_ID>.execute-api.us-east-1.amazonaws.com/prod";
document.addEventListener('DOMContentLoaded', cargarProductos);
const USER_ID = 'user-' + Math.random().toString(36).substr(2, 6);

async function cargarProductos() { try { const r = await fetch(API_URL + '/api/products'); const p = await r.json(); renderizarTabla(p); mostrarMensaje('Cargados', 'exito'); } catch (e) { mostrarMensaje('Error: ' + e.message, 'error'); } }

function renderizarTabla(productos) { const tbody = document.getElementById('productos-body'); tbody.innerHTML = ''; productos.forEach(p => { const tr = document.createElement('tr'); tr.innerHTML = `<td>${p.id}</td><td>${p.nombre}</td><td>${p.descripcion||'-'}</td><td>$${Number(p.precio).toLocaleString('es-CL')}</td><td>${p.stock}</td><td>${p.categoria||'-'}</td><td><button class="btn-carrito" onclick="agregarCarrito('${p.id}','${p.nombre.replace(/'/g,"\\'")}',${p.precio})">+ Carrito</button> <button class="btn-editar" onclick="editarProducto(${p.id},'${p.nombre.replace(/'/g,"\\'")}','${(p.descripcion||'').replace(/'/g,"\\'")}',${p.precio},${p.stock},'${(p.categoria||'').replace(/'/g,"\\'")}')">Editar</button> <button class="btn-eliminar" onclick="eliminarProducto(${p.id})">Eliminar</button></td>`; tbody.appendChild(tr); }); }

async function guardarProducto(event) { event.preventDefault(); const id = document.getElementById('producto-id').value; const datos = { nombre: document.getElementById('nombre').value, descripcion: document.getElementById('descripcion').value, precio: parseFloat(document.getElementById('precio').value), stock: parseInt(document.getElementById('stock').value), categoria: document.getElementById('categoria').value }; try { let r; if (id) { r = await fetch(API_URL+'/api/products/'+id, { method:'PUT', headers:{'Content-Type':'application/json'}, body:JSON.stringify(datos) }); } else { r = await fetch(API_URL+'/api/products', { method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify(datos) }); } mostrarMensaje(id?'Modificado':'Creado','exito'); limpiarFormulario(); cargarProductos(); } catch(e) { mostrarMensaje('Error','error'); } }

async function eliminarProducto(id) { if(!confirm('Eliminar?')) return; await fetch(API_URL+'/api/products/'+id,{method:'DELETE'}); mostrarMensaje('Eliminado','exito'); cargarProductos(); }

async function agregarCarrito(productId, nombre, precio) { await fetch(API_URL+'/api/cart',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({userId:USER_ID,productId,nombre,precio,cantidad:1})}); mostrarMensaje('Agregado al carrito','exito'); verCarrito(); }

async function verCarrito() { const r = await fetch(API_URL+'/api/cart?userId='+USER_ID); const data = await r.json(); const div = document.getElementById('carrito-contenido'); if(!data.items||data.items.length===0){div.innerHTML='<p>Carrito vacio</p>';return;} let html='<ul>'; data.items.forEach(i=>{html+=`<li>${i.nombre} x${i.cantidad} - $${(i.precio*i.cantidad).toLocaleString('es-CL')} <button onclick="quitarCarrito('${i.productId}')">X</button></li>`;}); html+=`</ul><p><strong>Total: $${data.total.toLocaleString('es-CL')}</strong></p><button class="btn-orden" onclick="crearOrden()">Confirmar Pedido</button>`; div.innerHTML=html; }

async function quitarCarrito(productId) { await fetch(API_URL+'/api/cart/'+productId+'?userId='+USER_ID,{method:'DELETE'}); verCarrito(); }

async function crearOrden() { const r = await fetch(API_URL+'/api/orders',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({userId:USER_ID})}); const data = await r.json(); mostrarMensaje('Su pedido fue procesado - Total: $'+data.total.toLocaleString('es-CL'),'exito'); verCarrito(); }

function editarProducto(id,n,d,p,s,c){document.getElementById('producto-id').value=id;document.getElementById('nombre').value=n;document.getElementById('descripcion').value=d;document.getElementById('precio').value=p;document.getElementById('stock').value=s;document.getElementById('categoria').value=c;document.getElementById('form-titulo').textContent='Editar (ID:'+id+')';}
function cancelarEdicion(){limpiarFormulario();}
function limpiarFormulario(){document.getElementById('producto-form').reset();document.getElementById('producto-id').value='';document.getElementById('form-titulo').textContent='Nuevo Producto';}
function mostrarMensaje(t,tipo){const m=document.getElementById('mensaje');m.textContent=t;m.className=tipo==='exito'?'mensaje-exito':'mensaje-error';setTimeout(()=>{m.textContent='';m.className='';},5000);}
// 2026 - Disenador asignatura: Ignacio A. Pastenet M.
