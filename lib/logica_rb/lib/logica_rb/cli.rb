# frozen_string_literal: true

require "json"
require "tempfile"
require "set"

require_relative "common/color"
require_relative "pipeline"
require_relative "parser"
require_relative "compiler/universe"
require_relative "transpiler"
require_relative "plan_validator"
require_relative "errors"

module LogicaRb
  class CLI
    COMMANDS = %w[parse infer_types show_signatures print plan validate-plan help version].freeze
    FORMATS = %w[query script plan].freeze
    ENGINES = %w[sqlite psql].freeze

    def self.main(argv)
      if argv.empty? || %w[help --help -h].include?(argv[0])
        puts help_text
        return 0
      end

      if %w[version --version -v].include?(argv[0])
        puts LogicaRb::VERSION
        return 0
      end

      if argv[0] == "validate-plan"
        plan_path = argv[1]
        if plan_path.nil? || plan_path.empty?
          warn "Not enough arguments. Run 'logica help' for help."
          return 1
        end

        begin
          json_text = plan_path == "-" ? $stdin.read : File.read(plan_path)
          plan_hash = JSON.parse(json_text)
          PlanValidator.validate!(plan_hash)
          puts "OK"
          return 0
        rescue JSON::ParserError => e
          warn "Invalid JSON: #{e.message}"
          return 1
        rescue PlanValidationError => e
          warn e.message
          return 1
        rescue Errno::ENOENT => e
          warn e.message
          return 1
        end
      end

      if argv.length < 2
        warn "Not enough arguments. Run 'logica help' for help."
        return 1
      end

      filename = argv[0]
      command = argv[1]

      unless COMMANDS.include?(command)
        puts Common::Color.format(
          "Unknown command {warning}{command}{end}. Available commands: {commands}.",
          { command: command, commands: COMMANDS.join(", ") }
        )
        return 1
      end

      predicate = nil
      remaining = argv[2..] || []
      if %w[print plan].include?(command)
        if remaining.empty? || remaining[0].start_with?("-")
          warn "Not enough arguments. Run 'logica help' for help."
          return 1
        end
        predicate = remaining.shift
      end

      options_args, user_flags_args = split_user_flags(remaining)
      options = parse_options(options_args)

      disable_color! if options[:no_color]

      import_root = options[:import_root] || import_root_from_env

      if user_flags_args.any? && !%w[print plan].include?(command)
        raise ArgumentError, "User flags are only supported for print/plan commands."
      end

      temp_file = nil
      if filename == "-"
        temp_file = Tempfile.new(["logica", ".l"])
        temp_file.write($stdin.read)
        temp_file.flush
        filename = temp_file.path
      end

      begin
        output = case command
        when "parse"
                   Pipeline.parse_file(File.read(filename), import_root: import_root)
        when "infer_types"
                   Pipeline.infer_types(File.read(filename), dialect: "psql", import_root: import_root)
        when "show_signatures"
                   Pipeline.show_signatures(File.read(filename), dialect: "psql", import_root: import_root)
        when "print", "plan"
                   user_flags = read_user_flags(filename, import_root: import_root, argv: user_flags_args)
                   engine = options[:engine]
                   format = options[:format] || (command == "plan" ? "plan" : "script")
                   format = "plan" if command == "plan"
                   validate_engine!(engine) if engine
                   validate_format!(format)

                   predicates = parse_predicates(predicate)
                   compilation = Transpiler.compile_file(
                     filename,
                     predicates: predicates,
                     format: format.to_sym,
                     engine: engine,
                     user_flags: user_flags,
                     import_root: import_root
                   )

                   if format == "plan"
                     compilation.plan_json(pretty: true)
                   else
                     compilation.sql(format)
                   end
        when "help"
                   help_text
        when "version"
                   LogicaRb::VERSION + "\n"
        when "validate-plan"
                   raise ArgumentError, "validate-plan must be called as: logica validate-plan <plan.json or ->"
        else
                   raise ArgumentError, "Unknown command: #{command}"
        end

        write_output(output, options[:output])
      rescue Parser::ParsingException => e
        e.show_message
        return 1
      rescue Compiler::RuleTranslate::RuleCompileException => e
        e.show_message
        return 1
      rescue Compiler::Functors::FunctorError => e
        e.show_message
        return 1
      rescue TypeInference::Research::Infer::TypeErrorCaughtException => e
        e.show_message
        return 1
      rescue UnsupportedEngineError => e
        warn "Unsupported engine: #{e.engine || e.message}"
        return 1
      rescue InvalidFormatError, ArgumentError, Errno::ENOENT => e
        warn e.message
        return 1
      ensure
        temp_file&.close
        temp_file&.unlink
      end

      0
    end

    def self.help_text
      <<~TEXT
        Usage:
          logica <l file | -> <command> [predicate(s)] [options] [-- user_flags...]
          logica validate-plan <plan.json or ->

        Commands:
          parse                     Print AST JSON.
          infer_types               Print typing JSON (psql dialect).
          show_signatures           Print predicate signatures (psql dialect).
          print <predicates>        Print SQL (default format=script).
          plan <predicates>         Print plan JSON (alias for print --format=plan).
          validate-plan             Validate plan JSON against schema and semantics.
          help
          version

        Options:
          --engine=sqlite|psql       Override @Engine/default (default sqlite).
          --format=query|script|plan Output format for print.
          --import-root=PATH         Override LOGICAPATH import root.
          --output=FILE              Write output to file (stdout by default).
          --no-color                 Disable ANSI color output.

        Notes:
          Imports are resolved via --import-root/LOGICAPATH. The CLI is file-based and does not expose allow_imports.
          For runtime-provided source in untrusted mode, use the Rails API (trusted: false) and configure allowed_import_prefixes.

        User flags:
          Use -- to separate Logica flags (defined by @DefineFlag) from CLI options.
          Example:
            logica program.l print Test --engine=sqlite --format=script -- --my_flag=123
      TEXT
    end

    def self.import_root_from_env
      roots = ENV["LOGICAPATH"]
      return nil if roots.nil? || roots.empty?
      split = roots.split(":")
      split.length > 1 ? split : split.first
    end

    def self.split_user_flags(args)
      idx = args.index("--")
      return [args, []] if idx.nil?
      [args[0...idx], args[(idx + 1)..] || []]
    end

    def self.parse_options(args)
      options = {
        format: nil,
        engine: nil,
        import_root: nil,
        output: nil,
        no_color: false,
      }

      idx = 0
      while idx < args.length
        arg = args[idx]
        case arg
        when /\A--engine(=(.*))?\z/
          value = Regexp.last_match(2) || next_arg_value(args, idx, "--engine")
          idx += 1 if Regexp.last_match(2).nil?
          options[:engine] = value
        when /\A--format(=(.*))?\z/
          value = Regexp.last_match(2) || next_arg_value(args, idx, "--format")
          idx += 1 if Regexp.last_match(2).nil?
          options[:format] = value
        when /\A--import-root(=(.*))?\z/
          value = Regexp.last_match(2) || next_arg_value(args, idx, "--import-root")
          idx += 1 if Regexp.last_match(2).nil?
          options[:import_root] = value
        when /\A--output(=(.*))?\z/
          value = Regexp.last_match(2) || next_arg_value(args, idx, "--output")
          idx += 1 if Regexp.last_match(2).nil?
          options[:output] = value
        when "--no-color"
          options[:no_color] = true
        else
          raise ArgumentError, "Unknown option: #{arg}"
        end
        idx += 1
      end

      options
    end

    def self.next_arg_value(args, idx, flag)
      value = args[idx + 1]
      raise ArgumentError, "Missing value for #{flag}" if value.nil? || value.start_with?("-")
      value
    end

    def self.parse_predicates(predicate_arg)
      predicate_arg.split(",").map(&:strip).reject(&:empty?)
    end

    def self.validate_engine!(engine)
      return if ENGINES.include?(engine)
      raise ArgumentError, "Unknown engine: #{engine}. Supported: #{ENGINES.join(', ')}"
    end

    def self.validate_format!(format)
      return if FORMATS.include?(format.to_s)
      raise InvalidFormatError, "Unknown format: #{format}"
    end

    def self.write_output(output, output_path)
      if output_path
        File.write(output_path, output)
      else
        print output
      end
    end

    def self.disable_color!
      return if @color_disabled
      LogicaRb::Common::Color.constants.grep(/\ACHR_/).each do |const|
        LogicaRb::Common::Color.send(:remove_const, const)
        LogicaRb::Common::Color.const_set(const, "")
      end
      @color_disabled = true
    end

    def self.read_user_flags(filename, import_root:, argv:)
      program_text = File.read(filename)
      parsed_rules = Parser.parse_file(program_text, import_root: import_root)["rule"]
      defined = Compiler::Annotations.extract_annotations(parsed_rules, restrict_to: ["@DefineFlag"])["@DefineFlag"].keys
      allowed = (defined + ["logica_default_engine"]).to_set

      user_flags = {}
      idx = 0
      while idx < argv.length
        arg = argv[idx]
        if arg.start_with?("--")
          key, value = arg[2..].split("=", 2)
          if value.nil?
            idx += 1
            value = argv[idx]
          end
          if key.nil? || key.empty? || value.nil?
            raise ArgumentError, "Invalid flag: #{arg}"
          end
          unless allowed.include?(key)
            raise ArgumentError, "Undefined command argument: #{key}"
          end
          user_flags[key] = value
        else
          raise ArgumentError, "Unexpected argument: #{arg}"
        end
        idx += 1
      end
      user_flags
    end
  end
end
