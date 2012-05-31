
#
#  Mirah REPL -- hacked to bits
#
#  assuming your ruby is jruby,
#  $ gem install mirah
#  $ ruby -rubygems repl.rb   
#  m> class Foo
#  m> def bar
#  m>   12
#  m> end
#  m> end
#  ...
#  m> puts Foo.new.bar
#  12
#
#
require 'mirah'

include Mirah::Util::ProcessErrors

# global grumble brumble--implicit state in commands
Mirah::AST.type_factory = Mirah::JVM::Types::TypeFactory.new
@tmp_classes = []
buffer=""
while true
  print " m> "
  line = gets

  break if line.chomp == "exit"

  buffer += line
  # from commands/base.rb & commands/parse.rb
  @state = Mirah::Util::CompilationState.new
  @state.command =:parse
  @state.save_extensions = false
  parser = Mirah::Parser.new(@state, false)

  # OMG! instance_variable_get
  transformer = parser.instance_variable_get :@transformer
  # from parser.rb + rescue
  begin
    ast = parser.parse_and_transform 'RePl'+Time.now.to_i.to_s, buffer
  rescue Mirah::SyntaxError => e
    if e.message =~ /expected \w+ before '<EOF>'/
      next
    else
      raise e
    end
  rescue NameError => e
    puts e
    next
  end
  buffer = ""
  p ast

  begin
    # from test/jvm/bytecode_test_helper.rb
    typer = Mirah::JVM::Typer.new(transformer)
    
    ast.infer(typer, true)
    
    typer.resolve(true)
  rescue Mirah::InferenceError => ex
    # from process_errors.rb
    puts ex
    if ex.node
      Mirah.print_error(ex.message, ex.position)
    else
      puts ex.message
    end
    next
  end

  begin
    compiler = Mirah::JVM::Compiler::JVMBytecode.new
    compiler.compile(ast)
  rescue Mirah::MirahError => ex
    # from process_errors.rb
    puts ex
    if ex.node
      Mirah.print_error(ex.message, ex.position)
    else
      puts ex.message
    end
    next
  end
  
  puts "compiled"

  classes = {}

  compiler.generate do |filename, builder|
    bytes = builder.generate
    FileUtils.mkdir_p(File.dirname(filename))
    open("#{filename}", "wb") do |f|
      f << bytes
    end
    classes[filename[0..-7]] = Mirah::Util::ClassLoader.binary_string bytes
  end
  puts "generated"
  
  loader = Mirah::Util::ClassLoader.new(JRuby.runtime.jruby_class_loader, classes)
  klasses = classes.keys.map do |name|
    cls = loader.load_class(name.tr('/', '.'))
    proxy = JavaUtilities.get_proxy_class(cls.name)
    @tmp_classes << "# {name}.class"
    proxy
  end
  puts "loaded"

  if klasses.size == 1 && klasses[0].name.start_with?("Java::Default::RePl")
    klasses[0].main(nil)
  end
end