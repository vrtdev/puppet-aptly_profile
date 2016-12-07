require 'logger'

# Wrapper class around Logger class that indents each message with the
# current stack depth.
# This automagically indents logs based on program execution
class IndentLogger < Logger
  attr_accessor :indent, :correction

  def initialize(logger, indent = ' ', correction = 0)
    @logger = logger
    @indent = indent
    @correction = correction
  end

  def add(severity, message = nil, progname = nil, &block)
    severity ||= UNKNOWN
    return true if severity < @level
    if message.nil?
      if block_given?
        message = yield
      else
        message = progname
        progname = @progname
      end
    end
    indent = @indent * (caller.size + @correction)
    message = indent + message unless message.nil?
    @logger.add(severity, message, progname, &block)
  end
end
