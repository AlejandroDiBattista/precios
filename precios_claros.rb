require 'open-uri'
require 'json'
require './base'

class PreciosClaros 
  class << self
    Sucursales = 'https://d3e6htiiul5ek9.cloudfront.net/prod/sucursales?offset=%i&limit=%i'
    Productos  = 'https://d3e6htiiul5ek9.cloudfront.net/prod/productos?string=pepsi&id_categoria=05&array_sucursales=10-2-601'

    def sucursales(pagina, max=10)
      open(Sucursales % [pagina, max]){|f| return JSON.parse(f.read)["sucursales"]}
    end

    def cantidad_sucursales
      actual, paso = 1, 2048 
      while paso > 0 
        s = sucursales(actual, 1).size
        actual += s == 0 ? -paso : +paso
        paso /= 2
      end
      actual
    end
  end
end

CamposSucursal = [:bandera_id, :lat, :lng, :sucursal_nombre, :id, :sucursal_tipo, :provincia, :direccion, :bandera_descripcion, :localidad, :comercio_razon_social, :comercio_id, :sucursal_id]

class Sucursal < Struct.new(*CamposSucursal)
  def self.cargar(h)
    new.cargar(h)
  end
  
  def cargar(h)
    h.each{|k, v| self[k.to_id] = v}
    normalizar
    self
  end
  
  def normalizar
    [:lat,:lng].each{|k|self[k] = self[k].to_f}
  end
  
end

class Sucursales
  include Enumerable
  
  def initialize
    limpiar
  end

  def limpiar
    @sucursales = {}
  end
  
  def registrar(s)
    puts  "  %-6s x %i" % [s.sucursal_id, @sucursales.keys.size]
    sincro{ @sucursales[s.sucursal_id] = s } 
  end
  
  def bajar
    puts "Hay %i sucursales " % (n = PreciosClaros.cantidad_sucursales)
    limpiar
    (1..n).step(10).procesar("Bajando Sucursales") do |i|
      PreciosClaros.sucursales(i).each{|s| registrar(Sucursal.cargar(s)) }
      escribir
    end
    puts @sucursales.size
  end
  
  def self.leer(origen=:precios_claros)
    origen = origen.to_s
    origen += '.json' unless origen['.json']

    open(origen,'r') do |f|
      Sucursales.new.cargar( JSON.parse(f.read) )
    end
  end 
  
  def escribir(destino=:precios_claros3)
    destino = destino.to_s
    destino += '.json' unless destino['.json']

    sincro do 
      File.open(destino, 'w'){|f| f.write(JSON.pretty_generate(to_h))}
    end
    self
  end
  
  def to_h
    {sucursales: @sucursales.values.map(&:to_h)}
  end
  
  def each
    @sucursales.each{|x|yield x}
  end

  def bajar(max=10)
    medir "Hay %i sucursales " % (paginas = PreciosClaros.cantidad_sucursales) do 
      limpiar
      inicio = Time.new
      queue = Queue.new
      (1..paginas).step(10).each{|item| queue << item }

      (1..times).procesar "Bajando precios" do 
          sucursales = PreciosClaros.sucursales(pagina)
          sucursales.each{|s| registrar(Sucursal.cargar(s))}
          escribir(:sucursales)
      end
    end
  end
end

b = Sucursales.new
b.bajar
p b.count