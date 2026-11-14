/**
 * Menu Smart — Google Apps Script para guardar la lista de compras.
 *
 * Qué hace cada vez que tocas "Guardar en Google Sheets":
 *   1. Hoja "Lista_Compras": una fila por ingrediente
 *      (Fecha guardado | Semana inicio | Semana fin | Ingrediente | Precio | Comprado).
 *      Si vuelves a guardar la misma semana, reemplaza esa semana (no duplica).
 *   2. Hoja "Historial_Compras": una fila resumen por cada guardado
 *      (Fecha | Semana inicio | Semana fin | Ingredientes | Total), como antes.
 *   Si alguna hoja no existe, la crea con sus encabezados.
 *
 * Cómo instalarlo (una sola vez):
 *   1. Abre tu Google Sheet → Extensiones → Apps Script.
 *   2. Reemplaza el código del proyecto por este archivo y guarda.
 *   3. Implementar → Administrar implementaciones → editar (lápiz) la
 *      implementación actual → Versión: "Nueva versión" → Implementar.
 *      Así el enlace /exec que ya usa la página no cambia.
 */

const HOJA_LISTA = 'Lista_Compras';
const HOJA_HISTORIAL = 'Historial_Compras';

function doPost(e) {
  try {
    const data = JSON.parse(e.postData.contents);
    const ss = SpreadsheetApp.getActiveSpreadsheet();
    const ahora = new Date();

    // 1) Una fila por ingrediente, reemplazando la semana si ya existía
    if (Array.isArray(data.items)) {
      const lista = obtenerHoja(ss, HOJA_LISTA,
        ['Fecha guardado', 'Semana inicio', 'Semana fin', 'Ingrediente', 'Precio (S/)', 'Comprado']);
      borrarSemana(lista, data.semanaInicio);
      const filas = data.items.map(function (it) {
        return [
          ahora,
          data.semanaInicio || '',
          data.semanaFin || '',
          it.nombre || '',
          (it.precio === null || it.precio === undefined) ? '' : Number(it.precio),
          it.comprado ? 'Sí' : 'No'
        ];
      });
      if (filas.length) {
        const inicio = lista.getLastRow() + 1;
        lista.getRange(inicio, 1, filas.length, filas[0].length).setValues(filas);
        lista.getRange(inicio, 5, filas.length, 1).setNumberFormat('"S/ "#,##0.00');
      }
    }

    // 2) Resumen en el historial
    const historial = obtenerHoja(ss, HOJA_HISTORIAL,
      ['Fecha', 'Semana inicio', 'Semana fin', 'Ingredientes', 'Total (S/)']);
    historial.appendRow([
      ahora,
      data.semanaInicio || '',
      data.semanaFin || '',
      data.ingredientes || '',
      (data.total === null || data.total === undefined) ? '' : Number(data.total)
    ]);
    historial.getRange(historial.getLastRow(), 5).setNumberFormat('"S/ "#,##0.00');

    return respuesta({ ok: true });
  } catch (err) {
    return respuesta({ ok: false, error: String(err) });
  }
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

/* Quita las filas de esa semana (columna B = Semana inicio) */
function borrarSemana(hoja, semanaInicio) {
  if (!semanaInicio) return;
  const ultima = hoja.getLastRow();
  if (ultima < 2) return;
  const valores = hoja.getRange(2, 2, ultima - 1, 1).getDisplayValues();
  for (let i = valores.length - 1; i >= 0; i--) {
    if (normalizarFecha(valores[i][0]) === semanaInicio) hoja.deleteRow(i + 2);
  }
}

/* Acepta "2026-11-16" o "16/11/2026" y devuelve "2026-11-16" */
function normalizarFecha(v) {
  const s = String(v).trim();
  const m = s.match(/^(\d{1,2})\/(\d{1,2})\/(\d{4})$/);
  if (m) return m[3] + '-' + ('0' + m[2]).slice(-2) + '-' + ('0' + m[1]).slice(-2);
  return s.slice(0, 10);
}

function respuesta(obj) {
  return ContentService.createTextOutput(JSON.stringify(obj))
    .setMimeType(ContentService.MimeType.JSON);
}
