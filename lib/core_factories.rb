unless Object.const_defined?(:CORE_GEM_ROOT)
  CORE_GEM_ROOT = File.dirname(File.dirname(__FILE__))

  Dir[File.join(CORE_GEM_ROOT, 'spec', 'factories', '*.rb')].each { |file| require(file) }
end
