require 'bbs2ch.rb'

#@thread = BBS2ch::Thread.new("http://pele.bbspink.com/test/read.cgi/okama/1327719321/l50")

def setup(&block)
  @setups << block
end

def tempura(arg)
  @args = arg
end

@setups = []
@args = []
load "tempra.tempra"

@setups.each do |setup|
  self.instance_eval &setup    
end

@thread = BBS2ch::Thread.new(@thread_url)
@args.each do |item|
  response = @thread.postMessage(item, @mail)
  puts response.body.toutf8
  sleep(15)
end
