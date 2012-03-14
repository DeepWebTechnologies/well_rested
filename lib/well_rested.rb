# encoding: utf-8

# require external dependencies
require 'active_support/core_ext/hash/indifferent_access'
require 'active_support/core_ext/hash/reverse_merge'

# require internal general-use libs
require 'key_transformer'
require 'generic_utils'

# require internal libs
require 'well_rested/api'
require 'well_rested/base'
require 'well_rested/utils'
require 'well_rested/json_formatter'
require 'well_rested/camel_case_formatter'

# Make sure 'bases' singularizes to 'base' instead of 'basis'.
# Otherwise, we get an error that no class Basis is found in Base.
ActiveSupport::Inflector.inflections do |inflect|
  inflect.irregular 'base', 'bases'
end

module WellRested
  def logger
    return Rails.logger if Utils.class_exists? 'Rails'
    return @logger if @logger

    require 'logger'
    @logger = Logger.new(STDERR)
    @logger.datetime_format = "%H:%M:%S"
    @logger
  end
end

