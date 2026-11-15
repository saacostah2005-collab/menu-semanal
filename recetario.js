/* ============================================================
   WeekMenuIA — Recetario para "Arma mi semana"
   Platos caseros (sobre todo peruanos). Cada línea es:

     Nombre | comidas | proteína | marcas | costo

   comidas:  d = desayuno, m = media mañana, a = almuerzo, c = cena
   proteína: pollo, carne, cerdo, pescado, menestra, huevo, lacteo,
             cereal, veg (verduras), fruta
   marcas:   p = peruano · n = apto para niños (sin picante ni cosas raras)
             c = lleva cerdo · f = solo fin de semana
   costo:    1 = económico · 2 = normal

   Para agregar un plato, copia una línea y cámbiala.
   ============================================================ */
(function(){
  const LISTA = `
Pan con palta y té|d|veg|pn|1
Pan con huevo revuelto|d|huevo|pn|1
Pan con queso fresco y café|d|lacteo|pn|1
Pan con pollo deshilachado|dc|pollo|pn|1
Pan con mantequilla y mermelada|d|veg|n|1
Pan con aceitunas y queso|d|lacteo|p|1
Pan con jamonada|d|cerdo|pnc|1
Pan con jamón del país|d|cerdo|pcf|2
Pan con chicharrón y camote|d|cerdo|pcf|2
Sánguche de atún|d|pescado|pn|1
Avena con manzana|dc|cereal|pn|1
Avena con plátano y canela|d|cereal|pn|1
Quinua con manzana|dc|cereal|pn|1
Maca con leche y pan|d|cereal|pn|1
Kiwicha con leche y pan|d|cereal|pn|1
Batido de plátano con pan|d|lacteo|pn|1
Jugo surtido y pan con queso|d|lacteo|pn|1
Emoliente y pan con queso|d|lacteo|p|1
Yogur con granola y fruta|dc|lacteo|n|2
Tortilla de verduras con pan|d|huevo|pn|1
Huevo sancochado con pan y té|d|huevo|pn|1
Tostadas con palta y huevo|d|huevo|n|2
Panqueques con miel|d|cereal|n|1
Camote sancochado con queso|d|lacteo|pn|1
Choclo con queso|dc|lacteo|pn|1
Tamal con salsa criolla|dc|pollo|pf|2
Humita con café|dc|veg|pf|2
Pan con camote y huevo frito|d|huevo|p|1
Manzana|m|fruta|pn|1
Plátano|m|fruta|pn|1
Mandarina|m|fruta|pn|1
Naranja|m|fruta|pn|1
Pera|m|fruta|pn|1
Granadilla|m|fruta|pn|1
Papaya picada|m|fruta|pn|1
Piña picada|m|fruta|pn|1
Sandía picada|m|fruta|pn|1
Uvas|m|fruta|pn|1
Mango|m|fruta|pn|1
Fresas con yogur|m|lacteo|n|2
Yogur|m|lacteo|n|1
Galletas de avena|m|cereal|n|1
Queso fresco con galletas|m|lacteo|pn|1
Mix de frutos secos|m|veg|n|2
Gelatina|m|veg|n|1
Mazamorra morada|m|cereal|pn|1
Arroz con leche|m|cereal|pn|1
Choclo sancochado|m|veg|pn|1
Huevo sancochado|m|huevo|pn|1
Ají de gallina|a|pollo|pn|1
Arroz con pollo|a|pollo|pn|1
Pollo al horno con papas|a|pollo|pn|1
Pollo saltado|a|pollo|pn|1
Estofado de pollo|a|pollo|pn|1
Tallarines rojos con pollo|a|pollo|pn|1
Tallarín saltado de pollo|a|pollo|pn|1
Pollo a la plancha con ensalada|ac|pollo|n|1
Chicharrón de pollo con yuca|a|pollo|pn|1
Arroz chaufa de pollo|a|pollo|pn|1
Pepián de choclo con pollo|a|pollo|p|1
Aguadito de pollo|ac|pollo|pn|1
Caldo de gallina|ac|pollo|pf|1
Causa rellena de pollo|a|pollo|pn|1
Milanesa de pollo con puré|a|pollo|n|1
Pollo en salsa de champiñones|a|pollo|n|2
Pollo con verduras al wok|ac|pollo|n|1
Tallarines verdes con pollo|a|pollo|pn|1
Arroz tapado de pollo|a|pollo|pn|1
Lomo saltado|a|carne|pn|2
Bistec a lo pobre|a|carne|p|2
Seco de res con frejoles|a|carne|p|2
Estofado de res|a|carne|pn|2
Tallarines verdes con bistec|a|carne|pn|2
Olluquito con carne|a|carne|p|1
Albóndigas en salsa con arroz|a|carne|pn|1
Carne guisada con papas|a|carne|pn|1
Bistec con arroz y ensalada|a|carne|pn|2
Saltado de vainitas con carne|a|carne|pn|1
Spaghetti a la boloñesa|a|carne|n|1
Puré con carne molida|a|carne|n|1
Rocoto relleno con pastel de papa|a|carne|p|2
Papa rellena con salsa criolla|a|carne|pn|1
Menestrón|a|carne|p|1
Sancochado|a|carne|pf|2
Asado de res con puré|a|carne|pn|2
Arroz tapado de carne|a|carne|pn|1
Chuleta de cerdo con ensalada|a|cerdo|pnc|1
Adobo de chancho con arroz|a|cerdo|pcf|2
Carapulcra con arroz|a|cerdo|pc|2
Chancho al horno con camote|a|cerdo|pcf|2
Chicharrón de cerdo con camote|a|cerdo|pcf|2
Pachamanca a la olla|a|cerdo|pcf|2
Ceviche de pescado|a|pescado|p|2
Sudado de pescado|a|pescado|pn|2
Pescado frito con arroz y ensalada|a|pescado|pn|1
Chicharrón de pescado|a|pescado|pn|2
Arroz con mariscos|a|pescado|p|2
Jalea de pescado|a|pescado|pf|2
Parihuela|a|pescado|pf|2
Pescado a la chorrillana|a|pescado|pn|2
Causa de atún|a|pescado|pn|1
Tallarines con atún|a|pescado|n|1
Bonito sudado|a|pescado|pn|1
Pescado al horno con verduras|ac|pescado|n|2
Escabeche de pescado|a|pescado|p|2
Chupe de camarones|a|pescado|pf|2
Lentejas con arroz y huevo frito|a|menestra|pn|1
Frejol canario con arroz|a|menestra|pn|1
Garbanzos guisados con arroz|a|menestra|pn|1
Pallares guisados con arroz|a|menestra|pn|1
Arvejas partidas con arroz|a|menestra|pn|1
Tacu tacu con huevo frito|a|menestra|pn|1
Frejoles con pescado frito|a|menestra|pn|1
Sopa de lentejas|ac|menestra|n|1
Papa a la huancaína con huevo|ac|huevo|pn|1
Tortilla de verduras con arroz|ac|huevo|pn|1
Pastel de acelga|a|huevo|pn|1
Tallarines verdes con huevo frito|a|huevo|pn|1
Arroz chaufa de verduras|ac|veg|pn|1
Locro de zapallo|a|veg|pn|1
Lasaña de verduras|a|veg|n|2
Solterito de queso|ac|lacteo|p|1
Ensalada de quinua|ac|cereal|p|1
Quinotto con champiñones|a|cereal|p|2
Tortitas de quinua con ensalada|ac|cereal|pn|1
Sopa de verduras|c|veg|pn|1
Caldo de pollo|c|pollo|pn|1
Sopa de fideos con pollo|c|pollo|pn|1
Crema de zapallo|c|veg|n|1
Crema de espinaca|c|veg|n|1
Sopa de quinua|c|cereal|pn|1
Sopa criolla|c|carne|p|1
Chilcano de pescado|c|pescado|p|1
Tortilla de verduras|c|huevo|pn|1
Huevos revueltos con tostadas|c|huevo|n|1
Puré con huevo frito|c|huevo|n|1
Papa sancochada con huevo y ensalada|c|huevo|pn|1
Sánguche de pollo|c|pollo|pn|1
Sánguche de atún con palta|c|pescado|pn|1
Ensalada de pollo|c|pollo|n|1
Ensalada de atún|c|pescado|n|1
Tortilla de atún|c|pescado|n|1
Wrap de pollo|c|pollo|n|2
Butifarra|c|cerdo|pc|1
Empanadas de carne|c|carne|pn|1
Hamburguesa casera|c|carne|nf|1
Pizza casera|c|lacteo|nf|2
Pollo a la brasa con papas|c|pollo|pnf|2
Anticuchos con papa|c|carne|pf|2
Salchipapa casera|c|cerdo|pcnf|1
Pan con queso y té|c|lacteo|pn|1
`;
  const CODIGOS = { d: 'desayuno', m: 'media_manana', a: 'almuerzo', c: 'cena' };
  window.RECETARIO = LISTA.trim().split('\n').map(linea => {
    const [n, comidas, prot, marcas, costo] = linea.split('|').map(x => x.trim());
    return {
      n,
      comidas: comidas.split('').map(ch => CODIGOS[ch]),
      prot,
      peru: marcas.includes('p'),
      ninos: marcas.includes('n'),
      cerdo: marcas.includes('c') || prot === 'cerdo',
      finde: marcas.includes('f'),
      costo: Number(costo) || 1
    };
  });
})();
