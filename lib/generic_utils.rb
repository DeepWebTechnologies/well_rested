module GenericUtils
  extend self

  # Return a class object given its name.
  def get_class(name)
    Kernel.const_get(name)
  rescue NameError
    nil
  end

  # Return whether a class exists for a given name.
  def class_exists?(name)
    get_class(name) != nil
  end

end

