require 'open3'

module MJML
  # Parser for MJML templates
  class Parser
    class InvalidTemplate < StandardError; end
    class ExecutableNotFound < StandardError; end

    ROOT_TAGS_REGEX = %r{<mjml.*>.*<\/mjml>}im

    def initialize
      raise ExecutableNotFound if MJML.executable_version.nil?
    end

    def call(template)
      call!(template)
    rescue InvalidTemplate
      nil
    end

    def call!(template)
      @template = template
      exec!
    end

    private

    def exec!
      raise InvalidTemplate if @template.empty?

      return @template if partial?

      out, err = should_get_outpout_from_file? ? output_from_file : output_from_memory
      parsed = parse_output(out)

      MJML.logger.error(err) unless err.empty?
      MJML.logger.warn(parsed[:warnings]) unless parsed[:warnings].empty?

      unless err.empty?
        message = [err, parsed[:warnings]].reject(&:empty?).join("\n")
        raise InvalidTemplate.new(message)
      end

      parsed[:output]
    end

    def partial?
      (@template.to_s =~ ROOT_TAGS_REGEX).nil?
    end

    def mjml_bin
      MJML::Config.bin_path
    end

    def cmd(file_path = nil)
      "#{mjml_bin} #{minify_output} #{validation_level} #{cmd_options}"
    end

    def cmd_options
      if should_get_outpout_from_file?
        "-i -o #{@temp_file.path}"
      else
        "-is"
      end
    end

    def minify_output
      if MJML::Feature::version[:major] >= 4
      '--config.minify true' if MJML::Config.minify_output
      else
        '--min' if MJML::Config.minify_output
      end
    end

    def validation_level
      if MJML::Feature::version[:major] >= 4
        "--config.validationLevel #{MJML::Config.validation_level}"
      else
        "--level=#{MJML::Config.validation_level}" if MJML::Feature.available?(:validation_level)
      end
    end

    def output_from_file
      @temp_file = Tempfile.new("mjml-template")
      _out, err, _sts = Open3.capture3(cmd, stdin_data: @template)
      @temp_file.rewind
      @temp_file.unlink
      return @temp_file.read, err
    end

    def output_from_memory
      out, err, _sts = Open3.capture3(cmd, stdin_data: @template)
      return out, err
    end

    def should_get_outpout_from_file?
      @template.to_s.size > 20_000
    end

    def parse_output(out)
      warnings = []
      output = []

      out.lines.each do |l|
        if l.strip.start_with?('Line')
          warnings << l
        else
          output << l
        end
      end

      { warnings: warnings.join("\n"), output: output.join }
    end
  end
end
