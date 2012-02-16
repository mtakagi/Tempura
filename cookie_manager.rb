class Cookie_Manager
  def initialize(prefix = "", use_tmp_dir = true)
    @prefix = prefix + ((prefix.size > 0) ? "_" : "")
    @use_tmp_dir = use_tmp_dir
    @storage = Cookie_Storage.new(cookie_directory + "/cookie")
  end

  def cookie_directory
    require 'tmpdir'
    require 'tempfile'
    
    Dir.chdir(Dir.tmpdir) do |path|
      temp_dirs = Dir.glob(@prefix + 'cookie_*')
      if temp_dirs.size == 0 then
        puts "Make Cookie directory."
        dir = Dir.mktmpdir(@prefix + "cookie_")
        return dir
      else
        puts "Cookie directory found."
        return path + "/" + temp_dirs[0]
      end
    end
  end
  
  def dump(&block)
    if block_given?
      @storage.cookies.each do |cookie|
        yield cookie
      end
    end
    
    return @storage.cookies
  end
    
  
  def method_missing(method, *args)
    # Cookie_Storage にあるメソッドは丸投げ
    if @storage.respond_to? method then
      return @storage.send(method, *args)
    else
      super
    end
  end
end

class Cookie_Storage
#  require 'marshal'
  attr :cookies
  
  def initialize(path)
    begin
      f = open(path, 'r')
    rescue
      p "Create cookie file."
      f = open(path, 'w')
      @cookies = Array.new
    else
      p "Load cookie file."
      @cookies = []
      begin
        @cookies = Marshal.load(f)
      rescue
        f = open(path, 'w')
        @cookies = Array.new
      else
        @cookies.uniq!
      end
    ensure
      f.close
    end
    
    ObjectSpace.define_finalizer(self, self.class.finalizer(path, @cookies))
  end
  
  def self.finalizer(file, array)
    proc {
      p "finalizer"
      if FileTest.exists?(file) && array.size > 0 then
        time = Time.now
      
        array = array.select { |cookie| 
          cookie.expires != nil &&
          cookie.expires > time &&
          cookie.domain != nil
        }
        array.uniq!
        f = open(file, 'w')
        dumped = Marshal.dump(array)
        f.write(dumped)
        f.close
      end
    }  
  end
  
  def add_cookie(cookie)
    @cookies << cookie
    array = @cookies.delete_if do |item|
      item.domain == cookie.domain && item.name == cookie.name && item.path == cookie.path
    end
  end
  
  def add_cookies_for_header(header, url)
    array = Cookie.cookies_from_header(header, url)
    array.each do |cookie|
      @cookies.delete_if do |item|
        item.domain == cookie.domain && item.name == cookie.name && item.path == cookie.path
      end
    end
    @cookies.concat(array)
  end
  
  def add_cookies_for_url(url)
    @cookies.concat(Cookie.cookies_from_url(url, cookie_string_for_url(url)))
  end
  
  def delete_cookie(cookie)
    @cookies.delete(cookie)
  end
  
  def cookies_for_url(url)
    require 'uri'
    host = URI.parse(url).host
    array = Array.new
    splited = host.split('.')
    splited.each_index do |index|
      break if index == splited.count - 1
      domain = "." + splited[index..splited.count].join('.')
      array.concat(@cookies.select { |cookie| 
        p "#{cookie.name} has no domain." if cookie.domain == nil
        p domain
        cookie.domain == domain 
        })
    end
    
    return array
  end
  
  def cookie_string_for_url(url)
    array = cookies_for_url(url)
    string = ""
    array.each_with_index do |cookie, index|
      string << "#{cookie.name}=#{cookie.value}" << (index != array.size - 1 ? "; " : "")
    end
    
    return string
  end
  
  def count
    return @cookies.count
  end
  
  def each(&block)
    @cookies.each &block
  end
end

class Time
  def self.cookie(expires)
    matched = expires.match(/\w{3}, (\d{2})-(\w{3})-(\d{4}) (\d{2}):(\d{2}):(\d{2}) GMT/)
    
    return Time.gm(matched[3], matched[2], matched[1], matched[4], matched[5], matched[6])
  end
end


class Cookie
  attr_accessor :name, :value, :expires, :domain, :path, :isHTTPOnly, :isSecure

#  alias :expires :max_age

  def initialize(cookie_string, url)
    array = cookie_string.split("; ")
    uri = URI.parse(url)
    @isHTTPOnly = false
    @isSecure = false

    array.each_with_index do |value, index|
      if value.downcase == "httponly" then
        @isHTTPOnly = true
      elsif value.downcase == "secure"
        @isSecure = true
      else
        parted = value.partition("=")
        if index == 0 then
          @name = parted[0]
          @value = parted[2]
        else
          case parted[0].downcase
          when "expires"
            @expires = Time.cookie(parted[2])
          when "path"
            @path = parted[2]
          when "domain"
            @domain = parted[2]
          end
        end
      end
    end
    
    @domain = "." + uri.host if !@domain
  end
    
  def ==(cookie)
    return @name == cookie.name && @value == cookie.value && @expires == cookie.expires &&
           @domain == cookie.domain && @path == cookie.path && @isHTTPOnly == cookie.isHTTPOnly && 
           @isSecure == cookie.isSecure
  end
  
  def self.cookies_from_header(header, url, &block)
    cookies = header.get_fields('Set-Cookie')
    array = Array.new
    cookies.each do |value|
      cookie = Cookie.new(value, url)
      yield cookie if block_given?
      array << cookie
    end if cookies != nil
    
    return array
  end
  
  def self.cookies_from_url(url, cookie = "", &block)
    require 'uri'
    uri = URI.parse(url)
    http = ""
    header = {"Cookie" => cookie}
    
    if uri.scheme == "https" then
      require 'net/https'
      require 'openssl'
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.ca_file = OpenSSL::X509::DEFAULT_CERT_FILE
      http.verify_mode = OpenSSL::SSL::VERIFY_PEER
      http.verify_depth = 5
    else
      require 'net/http'
      http = Net::HTTP.new(uri.host, uri.port)
    end
    
    response = http.head(uri.path, header)
    
    return self.cookies_from_header(response.header, url)
  end
end
 
#Cookie.cookies_from_url("https://www.google.com/").each do |cookie|
#  p "#{cookie.name}=#{cookie.value}"
#end

#manager = Cookie_Manager.new("2ch")
#c = ""
#manager.dump do |cookie|
#  p cookie.max_age
#end
#manager.add_cookies_for_url("http://www.google.com/")
#manager.add_cookies_for_url("http://www.google.co.jp/")
#manager.add_cookies_for_url("http://www.bing.com/")

#p manager.cookie_string_for_url("http://www.google.com/")
#p manager.cookie_string_for_url("http://www.bing.com/")