require 'open-uri'
require 'net/http'
require 'kconv'

require 'cookie_manager.rb'

#
#= 2ちゃんねる用モジュール
#
#Authors:: mtakagi
#Version:: 0.0.1 2012-01-23 mtakagi
#
#=== クラス
#
# - BBS2ch
# - Board
# - Thread
# - Dat
#
module BBS2ch
  VERSION = "0.0.1"
  USER_AGENT = "BBS2ch"
  
  #
  # インスタンス化の際に不正なURLが渡された時にraiseする例外
  #
  class InvalidURLException < Exception; end
  
  class DatMissingException < Exception; end
  
  #
  # BBSクラス
  #
  class BBS2ch
    
    # 生成時に渡されたURL
    attr :url
    
    #
    # イニシャライザ
    # 不正なURLを渡すと例外が発生する。不正なURLはクラスによって異る。
    #
    def initialize(url)
      @url = url
      unless self.send("validate_#{self.class.to_s.downcase}_url")
        raise InavalidURLException "Invalid #{self.class.to_s} URL"
      end
    end
        
    #
    # URLが不正かどうかチェックする
    #
    private
    def validate_url?(type)
      case type
      when "bbs2ch"
        if @url =~ /.*?(\w*)\.(2ch\.net|bbspink\.com)/ then
          true
        else
          false
        end
      when "board"
        return true
      when "thread"
        if @url =~ /.*?(\w+)\.(\w+\.\w+)\/test\/read.cgi\/(\w+)\/([0-9]+)\// then
          true
        else
          false
        end
      when "dat"
        if @url =~ /.*?(\w+)\.(2ch.net|bbspink.com)\/(.+?)\/dat\/[0-9]+.dat/
          true
        else
          false
        end
      end
    end
    
    #
    # method_missing
    # メソッド名にクラス名が含まれるメソッドをここで拾う
    #
    def method_missing(name, *args)
      if name.to_s =~ /^validate_.*?(\w+)_url?$/
        send(:validate_url?, $1)
      elsif name.to_s =~ /^.*?(\w+)_url$/
        return @url
      else
        super
      end
    end  
  end
  
  class Board < BBS2ch
    attr :thread_list
    
    def initialize(boardURL)
      super(boardURL)
      f = open(boardURL)
      f.read.scan(/\+(Samba24)=([0-9]+)/)
      f.close
      f.unlink
      self.send($1.downcase + '=', $2)
      subject = open(boardURL + "subject.txt")
      @thread_list = Array.new
      subject.readlines.each do |line|
        items = line.split("<>")
        thread = Hash.new
        thread.store('dat', items[0])
        thread.store('subject', items[1].chomp)
        @thread_list << thread
      end
      subject.close
      subject.unlink
      @array = boardURL.scan(/.*?(\w*)\.(2ch\.net|bbspink\.com)\/(\w+?)\//)[0];
      @postURI = URI.parse("http://#{@array[0]}.#{@array[1]}/test/bbs.cgi?guid=ON")
    end
    
    def parse_write_status(response)
      p response.body.toutf8
      response.body.toutf8.match(/.+?\<\!-- 2ch_X:(\w+?) --\>.+?/)
      p match
    end
    
    def post(subject, submit, referer, message, mail, name, cookie)
      body = "bbs=#{@array[2]}&subject=#{subject}&time=1&submit=#{submit}&FROM=#{name}&mail=#{mail}&MESSAGE=#{message}&suka=pontan"
      header = {
        "Host"           => @postURI.host,
        "Content-length" => "#{body.length}",
        "Referer"        => referer,
        "User-Agent"     => "Monazilla/1.00 (#{USER_AGENT}/#{VERSION})",
        "Connection"     => "close",
        'Cookie'         => cookie,
      }
      
      Net::HTTP.version_1_2
      http = Net::HTTP.new(@postURI.host, @postURI.port)
      
      p body, header
      
      return http.post(@postURI.path, body.tosjis, header)
    end
    
    def shinkisakusei(subject, cookie, message, mail, name)
      submit = "新規スレッド作成"
      referer = "http://#{@postURI.host}/#{@array[2]}/"
      
      p submit , referer
      
      response = post(subject, submit, referer, message, mail, name, cookie)
      
      parse_response(response)
      
      p response.header.get_fields('Set-Cookie')
      p response.body.toutf8
      
      return response
    end
    
    def shoudaku(subject, cookie, message, mail, name)
      referer = @postURI.to_s
      submit = "上記全てを承諾して書き込む"
      response = post(subject, submit, referer, message, mail, name, cookie)
      
      parse_response(response)
      
      p response.header.get_fields('Set-Cookie')
      p response.body.toutf8
      
      return response
    end
    
    def create_thread(subject, message, name = "", mail ="sage")
      manager = Cookie_Manager.new("2ch")
      url =  "http://#{@postURI.host}/"
      cookie = "yuki=akari; " + manager.cookie_string_for_url(url)
      response = shinkisakusei(subject, cookie, message, mail, name)
      manager.add_cookies_for_header(response.header, url)
      cookie = "yuki=akari; " + manager.cookie_string_for_url(url)
      
      p cookie
      
      response = shoudaku(subject, cookie, message, mail, name)
      manager.add_cookies_for_header(response.header, url)
      
      return response
      
      response = post(body, header)
      manager.add_cookies_for_header(response.header, url)
      parse_write_status(response)
#      submit = "上記全てを承諾して書き込む"
#      body = 
#      response = post(body, header)
#      manager.add_cookies_for_header(response.header, url)
      
      p cookie
    end
    
    def method_missing(name, *args)
      if name.to_s =~ /(\w+)=$/ then
        return self.instance_variable_set("@#{$1.downcase}", args[0])
      elsif name.to_s !~ /^.+?_url/ then
        return self.instance_variable_get("@#{name.to_s}")
      end
      super(name, *args)
    end
  end
  
  class Thread
    def initialize(threadURL)
      @hash = parseURL(threadURL)
      @postURI = URI.parse("http://#{@hash['server']}.#{@hash['domain']}/test/bbs.cgi?guid=ON")
    end
    
    def self.isValidThreadURL(url)
      return url =~ /.*?(\w+)\.(\w+\.\w+)\/test\/read.cgi\/(\w+)\/([0-9]+)\//
    end
    
    private
    def parseURL(threadURL)
      array = threadURL.scan(/http:\/\/(.+?)\.(\w+)\/test\/read.cgi\/(.+)\/([0-9]+)\//)[0]
      {
        "server" => array[0],
        "domain" => array[1],
        "bbs"    => array[2],
        "thread" => array[3]
      }
    end
    
    # http://age.s22.xrea.com/talk2ch/
    # <title>タグの中身</title>を調べる
    # * 書き込みが成功すると、書きこみましたという文字列が入る
    # * 書き込みが失敗すると、ＥＲＲＯＲという文字列が入る
    # * サーバの負荷が高く、書き込めない場合は、お茶でもという文字列が入る
    # * クッキー確認の場合は、書き込み確認という文字列が入る
    # 書き込み失敗エラーの内容を知るには、最初にくる<b>タグの中身を調べます。
    #
    # 
    # * 正常に書き込みが終了 <!-- 2ch_X:true -->
    # * 書き込みはしたが注意つき <!-- 2ch_X:false -->
    # * ＥＲＲＯＲ！のタイトル <!-- 2ch_X:error -->
    # * スレ立てなど書き込み別画面 <!-- 2ch_X:check -->
    # * クッキー確認画面 <!-- 2ch_X:cookie -->
    
    def parse_response(response)
      scaned = response.body.scan(/<!-- 2ch_X:(\w+) -->/)
      
      
      return scaned[0][0] if scaned.size > 0
    end
    
    def post(submit, referer, message, mail, name, cookie)
      body = "bbs=#{@hash['bbs']}&key=#{@hash['thread']}&time=1&submit=#{submit}&FROM=#{name}&mail=#{mail}&MESSAGE=#{message}&suka=pontan"
      header = {
        "Host"           => @postURI.host,
        "Content-length" => "#{body.length}",
        "Referer"        => referer,
        "User-Agent"     => "Monazilla/1.00 (#{USER_AGENT}/#{VERSION})",
         "Cookie"        => cookie,
        "Connection"     => "close",
       
      }
      
      Net::HTTP.version_1_2
      http = Net::HTTP.new(@postURI.host, @postURI.port)
      
      p body, header
      
      return http.post(@postURI.path, body.tosjis, header)
    end
    
    def kakikomi(cookie, message, mail, name)
      submit = "書き込む"
      referer = "http://#{@postURI.host}/#{@hash['bbs']}/"
      
      response = post(submit, referer, message, mail, name, cookie)
      
      return response
    end
    
    def shoudaku(cookie, message, mail, name)
      referer = @postURI.to_s
      submit = "上記全てを承諾して書き込む"
      response = post(submit, referer, message, mail, name, cookie)
      
#      parse_response(response)

      return response
    end
    
    public
    def postMessage(message, mail = "sage", name = "")
      manager = Cookie_Manager.new("2ch")
      url = "http://#{@postURI.host}/"
      cookie = "yuki=akari; " + manager.cookie_string_for_url(url)
      response = kakikomi(cookie, message, mail, name)
      manager.add_cookies_for_header(response.header, url)
      cookie = "yuki=akari; " + manager.cookie_string_for_url(url)
      if parse_response(response) == "cookie" then
#        response = kakikomi(cookie, message, mail, name)
#      else
        response = shoudaku(cookie, message, mail, name)
        manager.add_cookies_for_header(response.header, url)
      end
      
      return response
    end
    
    def dat_url
      "http://#{@hash['server']}.#{@hash['domain']}/#{@hash['bbs']}/dat/#{@hash['thread']}.dat"
    end
    
    def dat
      return Dat.new(dat_url)
    end
    
    def board
      return Board.new("http://#{@hash['server']}.#{@hash['domain']}/#{@hash['bbs']}/")
    end
  end
  
  class Dat < BBS2ch
    require 'zlib'
    attr :dat
    
    def initialize(datURL)
      super(datURL)
      header = {
        "Accept-Encoding" => "gzip"
      }
      uri = URI.parse(datURL)
      http = Net::HTTP.new(uri.host, uri.port)
      response = http.get(uri.path, header)
      @f = open(datURL, header)
      if response.code == "302" then
        raise DatMissingException #"Dat file is removed or Board is moved."
      end
      
      @dat = Zlib::GzipReader.new(@f).read
    end
    
    private
    def dateStringToTime(dateString)
      items = dateString.toutf8.scan(/([0-9]+)\/([0-9]+)\/([0-9]+).+? ([0-9]+):([0-9]+):([0-9]+)\.([0-9]+)/)[0]
      time = Time.local(items[0], items[1], items[2], items[3], items[4], items[5], items[6])
    end

    public
    
    def update
      header = {
#        "Accept-Encoding" => "gzip",
        "If-Modified-Since" => @f.meta['last-modified'],
        "Range"             => "bytes=#{@dat.size}-"
      }
      begin
        f = open(@f.base_uri, header)
      rescue => error
        p error
      else
#        @f.pos = @f.size
        @dat << f.read
#        p f.read.toutf8
#        @dat = Zlib::GzipReader.new(@f).read
        @f.meta['last-modified'] = f.meta['last-modified']
        return true
      end
    end
    
    def datArray
      require 'ostruct'
      array = Array.new
      
      @dat.lines.each do |line|
        struct = OpenStruct.new
        line.toutf8.chomp.split("<>").each_with_index do |item, index|
          case index
          when 0 then
            struct.name = item.sub(/ <\/b>(.+?)<b> /, "\\1")
          when 1 then
            struct.mail = item
          when 2 then
            dateAndID = item.split(" ID:")
            struct.kakikomiID = dateAndID[1]
            struct.time = dateStringToTime(dateAndID[0])
          when 3 then
            struct.message = item
          when 4 then
            struct.title = item
          end
        end
    #    puts struct.name
        array << struct
      end
  
      return array
    end
    
    def thread
      matched = @url.match(/.*?(\w+?).(2ch.net|bbspink.net)\/(\w+?)\/dat\/(\d+).dat/)
      return Thread.new("http://#{matched[1]}.#{matched[2]}/test/read.cgi/#{matched[3]}/#{mathced[4]}/")
    end
  end
    
  def printID(array)
    puts "書き込んだ人数は全体で" + array.size.to_s + "人"
    puts "末尾がiまたはI"
    puts (array.select {|item| item =~ /i$|I$/}).size
    puts "末尾がP"
    puts (array.select {|item| item =~ /P$/}).size
    puts "末尾がO"
    puts (array.select {|item| item =~ /O$/}).size
    puts "末尾がo"
    puts (array.select {|item| item =~ /o$/}).size
    puts "末尾がQ"
    puts (array.select {|item| item =~ /Q$/}).size
    puts "末尾が0"
    puts (array.select {|item| item =~ /0$/}).size
  end
end