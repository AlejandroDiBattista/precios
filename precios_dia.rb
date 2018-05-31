require 'open-uri'
require 'nokogiri'
require 'json'
require 'fileutils'
require './base'

Home       = "https://diaonline.supermercadosdia.com.ar"
BaseImagen = "https://d2p3an6os91m4y.cloudfront.net/app/public/spree/products"
DestinoImagen = "/Users/alejandro/Downloads/dia"

Categorias = {
  almacen:    '/c/almacen/9798',
  bebida:     '/c/bebidas/10570',
  perfumeria: '/c/perfumeria/10608',
  limpieza:   '/c/limpieza/10646',
  fresco:     '/c/frescos/10696',
}

class Producto < Struct.new(:url, :descripcion, :marca, :clasificacion, :precio, :imagen, :orden, :categoria, :activo, :historia)
  def self.cargar(datos)
    new.cargar(datos)
  end
  
  def id
    url.split("/").last
  end
  
  def cargar(datos)
    members.each{|k, v| self[k.to_sym] = datos[k.to_s]}
    normalizar
    self
  end
  
  def normalizar
    self.precio = self.precio.to_importe
  end
  
  def extraer_img(pagina)
    if img = pagina.css('img')[0]
      img["src"].gsub(BaseImagen,'')
    else
      ""
    end
  end
  
  def extraer(pagina, categoria)
    self.url           = pagina.css('a')[0]['href']
    self.descripcion   = pagina.css('h3').text.strip
    self.marca         = pagina.css('h2').text.strip
    self.precio        = pagina.css('span.price').text.to_importe
    self.categoria     = categoria
    self.clasificacion ||= nil
    self.imagen        = extraer_img(pagina)
    self
  end
  
  def extraer_clasificacion(pagina)
    self.clasificacion = pagina.css('ol.breadcrumb li').map{|x| x.css('a span').text.strip}
    self
  end
  
  def url_imagen(grande = false)
    origen = self.url
    origen = BaseImagen + origen unless origen['https:']
    origen = origen.gsub('gallery_small', 'gallery_large') if grande
    origen
  end

  def agregar(valor)
    if previo = self.historia.last
      if previo.last != valor.last #&& previo.first <= valor.first
        self.historia.pop if previo.first == valor.first
        self.historia << valor
      end
    else
      self.historia << valor
    end
  end
    
  def registrar(fecha=nil, precio=nil)
    fecha  ||= Time.new.to_fecha
    precio ||= self.precio

    self.historia ||= []
    agregar( [fecha, precio] )
  end
  
end

class Productos
  include Enumerable
  attr :datos
  attr :activo
  
  def initialize(lista=[])
    @datos = {}
    lista.each{|producto|@datos[producto.id] = producto}
  end
  
  def each
    @datos.values.each{|x|yield x}
  end
    
  def agregar(producto)
    producto.orden ||= @datos.values.size + 1 unless @datos[producto.id]
    producto.clasificacion ||= @datos[producto.id].clasificacion if @datos[producto.id]
    producto.activo = true
    producto.registrar
    
    @datos[producto.id] = producto
  end

  def registrar(id, fecha, precio)
    if producto = @datos[id]
      producto.registrar(fecha, precio)
    end
  end
  
  def self.leer(origen = :dia)
    origen = origen.to_s
    origen += '.json' unless origen['.json']
    origen = './datos/'+ origen unless origen['/']

    File.open(origen,'r') do |f|
      Productos.new.cargar( JSON.parse(f.read) )
    end
  end 
  
  def escribir(destino = :dia)
    destino = destino.to_s
    destino += '.json' unless destino['.json']
    destino = './datos/'+ destino unless destino['/']

    File.open(destino, 'w') do |f|
      f.write(JSON.pretty_generate(datos.values.map(&:to_h)))
    end
    self
  end
  
  def self.copiar(origen = :dia)
    origen  = origen.to_s
    origen += '.json' unless origen['.json']
    origen = './datos/'+ origen unless origen['/']
    
    destino = "#{Time.now.to_fecha}.json"
    destino = './datos/'+ destino unless destino['/']
    
    ok = File.exist?(origen) && !File.exist?(destino)
    puts "COPIANDO #{origen} => #{destino} #{ok ? '😀' : '🤫' }"
    FileUtils.copy origen, destino if ok
  end
  
  def cargar(lista)
    lista.each{|producto| agregar(Producto.cargar(producto)) }
    self
  end
  
  def cantidad_paginas(pagina)
    (pagina.css('i.total').text.to_f / 20 + 1).to_i
  end
  
  def bajar_categoria(categoria)
    url = Categorias[categoria]
    paginas = cantidad_paginas(bajar(url))
    (1..paginas).procesar( "Bajando #{categoria}", 10) do |i|
      items = bajar(url, i).css('ul.products ul.products li')
      sincro do 
        items.each{|item| agregar( Producto.new.extraer(item, categoria) )}
      end
    end
  end
    
  def bajar_clasificaciones
    select{|x|!x.clasificacion}.procesar("Bajando Clasificaciones", 10) do |producto|
      productos = bajar(producto.url)
      sincro do 
        producto.extraer_clasificacion( productos ) 
      end
    end
  end
  
  def bajar_imagenes(saltar=0)
    lista = select{|x| !existe(destino_imagen(x.orden))}
    lista[saltar..-1].procesar("Bajando Imagenes", 5){|x|bajar_imagen(x.imagen, x.orden)}
  end
  
  def self.actualizar(o={})
    o = {precios: true, imagenes: true, clasificaciones: true, forzar: false, copiar: true}.merge(o)
    copiar if o[:copiar]
        
    if o[:precios]
      tmp = Productos.leer
      tmp.each{|x|x.activo = false}
      medir "Actualizando Categorias" do 
        Categorias.keys.each{|categoria| tmp.bajar_categoria(categoria)}
      end
      tmp.escribir
    end
    
    if o[:imagenes]
      tmp = Productos.leer
      tmp.bajar_imagenes
      tmp.escribir
    end
    
    if o[:clasificaciones]
      tmp = Productos.leer
      tmp.each{|x|x.clasificacion = nil} if o[:forzar]
      tmp.bajar_clasificaciones
      tmp.escribir
    end
  end
end

def bajar(url, pagina=nil)
  url = Home + url unless url["https:"]
  url += "?page=#{pagina}" if pagina && ! url["?page="]

  open(url,'r') do |f|
    pagina = Nokogiri::HTML(f) 
    return block_given? ? yield( pagina ) : pagina
  end
end

def existe(destino)
  File.exist?(destino_imagen(destino))
end

def bajar_imagen(origen, destino, grande=false)
  origen  = url_imagen(origen,grande)
  destino = destino_imagen(destino)
  unless existe(destino)
    begin
      File.open(origen, 'r'){|o| File.open(destino, 'wb'){|d| d.puts o.read }}
    rescue
      puts "🙁 #{origen}"
    end
  end
end

def url_imagen(origen, grande=false)
  origen = BaseImagen + origen unless origen['https:']
  origen = origen.gsub('gallery_small', 'gallery_large') if grande
  origen
end

def destino_imagen(origen)
  origen = "%05i.jpg" % origen if origen.is_a?(Fixnum)
  origen += '.jpg' unless origen['.jpg']
  origen = DestinoImagen + "/" + origen unless origen['/']
  origen
end

class Productos
  def marcas
    map(&:marca)
  end
  
  def categorias
    map(&:categoria)
  end
  
  def clasificaciones
    map(&:clasificacion)
  end
  
  def filtrar(&condicion)
    Productos.new(select{|x|condicion.(x)})
  end
  
  def ordenar(*campos, &condicion)
    invertir = Symbol === campos.first ? false : campos.shift 
    unless block_given?
      condicion = campos.size == 0 ? lambda{|x|x.first} : lambda{|x| campos.map{|campo| x[campo]} }
    end
    lista = sort_by{|x|condicion.(x)}
    lista = lista.reverse if invertir
    Productos.new(lista)
  end
  
  def invertir
    Productos.new(map{|x|x}.reverse)
  end
  
  def top(n=9999)
    Productos.new(first(n))
  end
  
  def listar(*campos, &formato)
    campos        = first.members if campos.size == 0
    descripcion ||= String === campos.first ? campos.shift : "LISTADO <*>"
    formato       = lambda{|x| x} unless block_given?
    
    puts "▶︎ #{descripcion.gsub('*', campos.join('|'))} ##{count}"
    each_with_index do |x,i|
      valores = campos.map{|campo|x[campo]}
      puts " %4i• #{formato.(valores) % valores}" % (i+1)
    end
    puts "◼︎"
  end
  
end

class Productos
  def self.listar_historia
    Dir['./datos/*.json'].select{|x|x[/[0-9]{4}-[0-9]{2}-[0-9]{2}/]}.sort
  end
  def self.generar_historia
    a = Productos.leer
    a.each{|x|x.historia = []}
    listar_historia.procesar("Generando Historia") do |x|
      fecha = File.basename(x, ".rb")
      b = Productos.leer(x)
      b.each{|x| a.registrar(x.id, fecha, x.precio) }
    end
    a.escribir
  end
end

class Producto
  def aumento
    historia.last.last.to_f / historia.first.last.to_f - 1
  end
end

Productos.actualizar

a = Productos.generar_historia

s = a.map{|x|x.historia.size}
p s.contar.sort_by(&:first)

# pp a.select{|x|x.historia.size == 4}.first(10)