/**
 * Menu Smart — Google Apps Script (lista de compras compartida + historial).
 *
 * La lista vive en tu Google Sheet, así todos los celulares ven la misma:
 *   • Hoja "Lista_Actual": la lista de compras de ahora
 *       ID (oculta) | Ingrediente | Precio (S/) | Comprado
 *     Tú y tu familia agregan, quitan y marcan desde la página, y se ve en todos.
 *   • Hoja "Historial_Compras": un resumen cada vez que tocas "Guardar en historial"
 *       Fecha | Semana inicio | Semana fin | Ingredientes | Total (S/)
 *   • Hoja "Historial_Detalle": el detalle de ese guardado, un ingrediente por fila
 *       Fecha | Semana inicio | Semana fin | Ingrediente | Precio (S/) | Comprado
 *   Si alguna hoja no existe, se crea sola con sus encabezados.
 *   La página historial.html lee estas dos hojas para mostrar lo gastado por semana.
 *
 * Cómo instalarlo (una sola vez):
 *   1. Abre tu Google Sheet → Extensiones → Apps Script.
 *   2. Borra el código que hay y pega todo este archivo. Guarda (ícono de disquete).
 *   3. Implementar → Administrar implementaciones → lápiz (editar) en la
 *      implementación actual → Versión: "Nueva versión" → Implementar.
 *      Así el enlace /exec que ya usa la página no cambia.
 *   (Debe seguir con "Ejecutar como: Yo" y "Quién tiene acceso: Cualquier persona".)
 */

const HOJA_LISTA = 'Lista_Actual';
const HOJA_HISTORIAL = 'Historial_Compras';
const HOJA_DETALLE = 'Historial_Detalle';

/* Leer la lista:      .../exec?action=lista
   Leer el historial:  .../exec?action=historial */
function doGet(e) {
  try {
    const accion = (e && e.parameter && e.parameter.action) || 'lista';
    if (accion === 'lista') return respuesta({ ok: true, items: leerLista() });
    if (accion === 'historial') return respuesta({ ok: true, registros: leerHistorial() });
    return respuesta({ ok: false, error: 'Acción desconocida: ' + accion });
  } catch (err) {
    return respuesta({ ok: false, error: String(err) });
  }
}

/* Cambiar la lista (action: "ops") o guardar en el historial (action: "historial") */
function doPost(e) {
  try {
    const data = JSON.parse(e.postData.contents);

    if (data.action === 'ops') {
      // Un cambio a la vez, para que dos celulares no se pisen
      const lock = LockService.getScriptLock();
      lock.waitLock(20000);
      try {
        let items = leerLista();
        (data.ops || []).forEach(function (op) { items = aplicarOp(items, op); });
        escribirLista(items);
        return respuesta({ ok: true, items: items });
      } finally {
        lock.releaseLock();
      }
    }

    // "historial" (también acepta el formato antiguo, sin "action")
    guardarHistorial(data);
    return respuesta({ ok: true });
  } catch (err) {
    return respuesta({ ok: false, error: String(err) });
  }
}

/* ---------- lista actual ---------- */

function hojaLista() {
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  let hoja = ss.getSheetByName(HOJA_LISTA);
  if (!hoja) {
    hoja = ss.insertSheet(HOJA_LISTA);
    hoja.getRange(1, 1, 1, 4).setValues([['ID', 'Ingrediente', 'Precio (S/)', 'Comprado']]).setFontWeight('bold');
    hoja.setFrozenRows(1);
    hoja.hideColumns(1);
    hoja.setColumnWidth(2, 220);
  }
  return hoja;
}

function leerLista() {
  const hoja = hojaLista();
  const ultima = hoja.getLastRow();
  if (ultima < 2) return [];
  return hoja.getRange(2, 1, ultima - 1, 4).getValues()
    .map(function (r) {
      const precio = (r[2] === '' || r[2] === null) ? null : Number(r[2]);
      return {
        id: String(r[0]),
        name: String(r[1]),
        price: (precio === null || isNaN(precio)) ? null : precio,
        done: r[3] === true || String(r[3]).toLowerCase() === 'sí' || String(r[3]).toLowerCase() === 'si'
      };
    })
    .filter(function (it) { return it.id && it.name; });
}

function escribirLista(items) {
  const hoja = hojaLista();
  const ultima = hoja.getLastRow();
  if (ultima > 1) hoja.getRange(2, 1, ultima - 1, 4).clearContent();
  if (!items.length) return;
  const filas = items.map(function (it) {
    return [it.id, it.name, it.price === null || it.price === undefined ? '' : Number(it.price), it.done ? 'Sí' : 'No'];
  });
  hoja.getRange(2, 1, filas.length, 4).setValues(filas);
  hoja.getRange(2, 3, filas.length, 1).setNumberFormat('"S/ "#,##0.00');
}

/* Las mismas operaciones que hace la página */
function aplicarOp(items, op) {
  if (!op || !op.type) return items;
  switch (op.type) {
    case 'add': {
      const it = op.item || {};
      if (!it.id || !it.name) return items;
      if (items.some(function (x) { return x.id === it.id; })) return items;
      const nuevo = { id: String(it.id), name: String(it.name).slice(0, 80), price: limpiarPrecio(it.price), done: !!it.done };
      const copia = items.slice();
      const i = (typeof op.index === 'number') ? Math.max(0, Math.min(op.index, copia.length)) : copia.length;
      copia.splice(i, 0, nuevo);
      return copia;
    }
    case 'update':
      return items.map(function (x) {
        if (x.id !== op.id) return x;
        const f = op.fields || {};
        return {
          id: x.id,
          name: f.name !== undefined ? String(f.name).slice(0, 80) : x.name,
          price: f.price !== undefined ? limpiarPrecio(f.price) : x.price,
          done: f.done !== undefined ? !!f.done : x.done
        };
      });
    case 'delete':
      return items.filter(function (x) { return x.id !== op.id; });
    case 'uncheckAll':
      return items.map(function (x) { return { id: x.id, name: x.name, price: x.price, done: false }; });
    case 'clear':
      return [];
    default:
      return items;
  }
}

function limpiarPrecio(p) {
  if (p === null || p === undefined || p === '') return null;
  const n = Number(p);
  return isNaN(n) || n < 0 ? null : Math.round(n * 100) / 100;
}

/* ---------- historial ---------- */

function guardarHistorial(data) {
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  const ahora = new Date();

  const historial = obtenerHoja(ss, HOJA_HISTORIAL, ['Fecha', 'Semana inicio', 'Semana fin', 'Ingredientes', 'Total (S/)']);
  historial.appendRow([
    ahora,
    data.semanaInicio || '',
    data.semanaFin || '',
    data.ingredientes || '',
    (data.total === null || data.total === undefined) ? '' : Number(data.total)
  ]);
  historial.getRange(historial.getLastRow(), 5).setNumberFormat('"S/ "#,##0.00');

  if (Array.isArray(data.items) && data.items.length) {
    const detalle = obtenerHoja(ss, HOJA_DETALLE, ['Fecha', 'Semana inicio', 'Semana fin', 'Ingrediente', 'Precio (S/)', 'Comprado']);
    const filas = data.items.map(function (it) {
      return [ahora, data.semanaInicio || '', data.semanaFin || '', it.nombre || '',
              limpiarPrecio(it.precio) === null ? '' : limpiarPrecio(it.precio), it.comprado ? 'Sí' : 'No'];
    });
    const inicio = detalle.getLastRow() + 1;
    detalle.getRange(inicio, 1, filas.length, 6).setValues(filas);
    detalle.getRange(inicio, 5, filas.length, 1).setNumberFormat('"S/ "#,##0.00');
  }
}

/* Devuelve cada guardado del historial con su detalle por ingrediente.
   El resumen y el detalle de un mismo guardado comparten la misma Fecha. */
function leerHistorial() {
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  const tz = ss.getSpreadsheetTimeZone();
  const clave = function (v) {
    return v instanceof Date ? Utilities.formatDate(v, tz, 'yyyy-MM-dd HH:mm:ss') : String(v);
  };
  const dia = function (v) {
    if (v instanceof Date) return Utilities.formatDate(v, tz, 'yyyy-MM-dd');
    const s = String(v || '').trim();
    const m = s.match(/^(\d{1,2})\/(\d{1,2})\/(\d{4})$/);
    if (m) return m[3] + '-' + ('0' + m[2]).slice(-2) + '-' + ('0' + m[1]).slice(-2);
    return s.slice(0, 10);
  };
  const numero = function (v) {
    if (v === '' || v === null || v === undefined) return null;
    const n = Number(v);
    return isNaN(n) ? null : n;
  };

  // Detalle agrupado por guardado
  const detallePorFecha = {};
  const hojaDet = ss.getSheetByName(HOJA_DETALLE);
  if (hojaDet && hojaDet.getLastRow() > 1) {
    hojaDet.getRange(2, 1, hojaDet.getLastRow() - 1, 6).getValues().forEach(function (r) {
      if (!r[3]) return;
      const k = clave(r[0]);
      (detallePorFecha[k] = detallePorFecha[k] || []).push({
        nombre: String(r[3]),
        precio: numero(r[4]),
        comprado: String(r[5]).toLowerCase() === 'sí' || String(r[5]).toLowerCase() === 'si' || r[5] === true
      });
    });
  }

  const registros = [];
  const hojaHist = ss.getSheetByName(HOJA_HISTORIAL);
  if (hojaHist && hojaHist.getLastRow() > 1) {
    const ancho = Math.min(5, hojaHist.getLastColumn());
    hojaHist.getRange(2, 1, hojaHist.getLastRow() - 1, ancho).getValues().forEach(function (r) {
      if (!r[0]) return;
      const fecha = r[0] instanceof Date ? r[0] : new Date(r[0]);
      registros.push({
        fecha: isNaN(fecha) ? String(r[0]) : fecha.toISOString(),
        semanaInicio: dia(r[1]),
        semanaFin: dia(r[2]),
        ingredientes: String(r[3] || ''),
        total: ancho >= 5 ? numero(r[4]) : null,
        items: detallePorFecha[clave(r[0])] || []
      });
    });
  }
  return registros;
}

function obtenerHoja(ss, nombre, encabezados) {
  let hoja = ss.getSheetByName(nombre);
  if (!hoja) {
    hoja = ss.insertSheet(nombre);
    hoja.appendRow(encabezados);
    hoja.getRange(1, 1, 1, encabezados.length).setFontWeight('bold');
    hoja.setFrozenRows(1);
  }
  return hoja;
}

function respuesta(obj) {
  return ContentService.createTextOutput(JSON.stringify(obj))
    .setMimeType(ContentService.MimeType.JSON);
}
