module MethodDecorators
  def self.extended(klass)
    klass.class_eval do
      @@__decorated_methods ||= {}
      def self.__decorated_methods
        @@__decorated_methods
      end

      def self.__decorated_methods_set(k, v)
        @@__decorated_methods[k] = v
      end
    end
  end

  # first, when you write a contract, the decorate method gets called which
  # sets the @decorators variable. Then when the next method after the contract
  # is defined, method_added is called and we look at the @decorators variable
  # to find the decorator for that method. This is how we associate decorators
  # with methods.
  def method_added(name)
    common_method_added name, false
    super
  end

  # For Ruby 1.9
  def singleton_method_added name
    common_method_added name, true
    super
  end

  def common_method_added name, is_class_method
    return unless @decorators

    decorators = @decorators.dup
    @decorators = nil

    klass, args = decorators[0]
      # a reference to the method gets passed into the contract here. This is good because
      # we are going to redefine this method with a new name below...so this reference is
      # now the *only* reference to the old method that exists.
    if args[-1].is_a? Hash
      # internally we just convert that return value syntax back to an array
      contracts = args[0, args.size - 1] + args[-1].keys
    else
      fail "It looks like your contract for #{method} doesn't have a return value. A contract should be written as `Contract arg1, arg2 => return_value`."
    end
      
      decorator = {
        :klass => self,
        :args_contracts => contracts[0, contracts.size - 1],
        :ret_contract => contracts[-1]
      }
=begin
      if is_class_method
        decorator[:method] = :"old_#{name}"
      else
        decorator[:method] = :"old_#{name}"
      end
=end
      if is_class_method
        decorator[:method] = method(name)
      else
        decorator[:method] = instance_method(name)
      end

    __decorated_methods_set(name, decorator)
    #alias_method :"old_#{name}", name

    args_validators = []
    decorator[:args_contracts].each_with_index do |contract, i|
      args_validators << Contract.make_validator(contract, i)
    end

    # in place of this method, we are going to define our own method. This method
    # just calls the decorator passing in all args that were to be passed into the method.
    # The decorator in turn has a reference to the actual method, so it can call it
    # on its own, after doing it's decorating of course.
    foo = %{
      def #{is_class_method ? "self." : ""}#{name}(*args, &blk)
        this = self#{is_class_method ? "" : ".class"}
        hash = this.__decorated_methods[#{name.inspect}]
        args_contracts = hash[:args_contracts]

        _args = blk ? args + [blk] : args

#{args_validators.join("\n")}
        hash[:method].bind(self).call(*args, &blk)
        #this.send(hash[:method], *args, &blk)
      end
      }
      
      puts foo
      class_eval foo, __FILE__, __LINE__ + 1
  end    

  def decorate(klass, *args)
    @decorators ||= []
    @decorators << [klass, args]
  end
end

class Decorator
  # an attr_accessor for a class variable:
  class << self; attr_accessor :decorators; end

  def self.inherited(klass)
    name = klass.name.gsub(/^./) {|m| m.downcase}

    return if name =~ /^[^A-Za-z_]/ || name =~ /[^0-9A-Za-z_]/

    # the file and line parameters set the text for error messages
    # make a new method that is the name of your decorator.
    # that method accepts random args and a block.
    # inside, `decorate` is called with those params.
    MethodDecorators.module_eval <<-ruby_eval, __FILE__, __LINE__ + 1
      def #{klass}(*args, &blk)
        decorate(#{klass}, *args, &blk)
      end
    ruby_eval
  end

  def initialize(klass, method)
    @method = method
  end
end
