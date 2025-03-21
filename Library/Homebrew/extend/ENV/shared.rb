# frozen_string_literal: true

require "compilers"
require "development_tools"

# Homebrew extends Ruby's `ENV` to make our code more readable.
# Implemented in {SharedEnvExtension} and either {Superenv} or
# {Stdenv} (depending on the build mode).
# @see Superenv
# @see Stdenv
# @see https://www.rubydoc.info/stdlib/Env Ruby's ENV API
module SharedEnvExtension
  include CompilerConstants

  # @private
  CC_FLAG_VARS = %w[CFLAGS CXXFLAGS OBJCFLAGS OBJCXXFLAGS].freeze
  # @private
  FC_FLAG_VARS = %w[FCFLAGS FFLAGS].freeze
  # @private
  SANITIZED_VARS = %w[
    CDPATH CLICOLOR_FORCE
    CPATH C_INCLUDE_PATH CPLUS_INCLUDE_PATH OBJC_INCLUDE_PATH
    CC CXX OBJC OBJCXX CPP MAKE LD LDSHARED
    CFLAGS CXXFLAGS OBJCFLAGS OBJCXXFLAGS LDFLAGS CPPFLAGS
    MACOSX_DEPLOYMENT_TARGET SDKROOT DEVELOPER_DIR
    CMAKE_PREFIX_PATH CMAKE_INCLUDE_PATH CMAKE_FRAMEWORK_PATH
    GOBIN GOPATH GOROOT PERL_MB_OPT PERL_MM_OPT
    LIBRARY_PATH LD_LIBRARY_PATH LD_PRELOAD LD_RUN_PATH
  ].freeze

  # @private
  def setup_build_environment(formula = nil, args: nil)
    @formula = formula
    @args = args
    reset
  end

  # @private
  def reset
    SANITIZED_VARS.each { |k| delete(k) }
  end

  def remove_cc_etc
    keys = %w[CC CXX OBJC OBJCXX LD CPP CFLAGS CXXFLAGS OBJCFLAGS OBJCXXFLAGS LDFLAGS CPPFLAGS]
    removed = Hash[*keys.flat_map { |key| [key, self[key]] }]
    keys.each do |key|
      delete(key)
    end
    removed
  end

  def append_to_cflags(newflags)
    append(CC_FLAG_VARS, newflags)
  end

  def remove_from_cflags(val)
    remove CC_FLAG_VARS, val
  end

  def append_to_cccfg(value)
    append("HOMEBREW_CCCFG", value, "")
  end

  def append(keys, value, separator = " ")
    value = value.to_s
    Array(keys).each do |key|
      old = self[key]
      if old.nil? || old.empty?
        self[key] = value
      else
        self[key] += separator + value
      end
    end
  end

  def prepend(keys, value, separator = " ")
    value = value.to_s
    Array(keys).each do |key|
      old = self[key]
      self[key] = if old.nil? || old.empty?
        value
      else
        value + separator + old
      end
    end
  end

  def append_path(key, path)
    self[key] = PATH.new(self[key]).append(path)
  end

  # Prepends a directory to `PATH`.
  # Is the formula struggling to find the pkgconfig file? Point it to it.
  # This is done automatically for keg-only formulae.
  # <pre>ENV.prepend_path "PKG_CONFIG_PATH", "#{Formula["glib"].opt_lib}/pkgconfig"</pre>
  # Prepending a system path such as /usr/bin is a no-op so that requirements
  # don't accidentally override superenv shims or formulae's `bin` directories, e.g.
  # <pre>ENV.prepend_path "PATH", which("emacs").dirname</pre>
  def prepend_path(key, path)
    return if %w[/usr/bin /bin /usr/sbin /sbin].include? path.to_s

    self[key] = PATH.new(self[key]).prepend(path)
  end

  def prepend_create_path(key, path)
    path = Pathname.new(path) unless path.is_a? Pathname
    path.mkpath
    prepend_path key, path
  end

  def remove(keys, value)
    return if value.nil?

    Array(keys).each do |key|
      next unless self[key]

      self[key] = self[key].sub(value, "")
      delete(key) if self[key].empty?
    end
  end

  def cc
    self["CC"]
  end

  def cxx
    self["CXX"]
  end

  def cflags
    self["CFLAGS"]
  end

  def cxxflags
    self["CXXFLAGS"]
  end

  def cppflags
    self["CPPFLAGS"]
  end

  def ldflags
    self["LDFLAGS"]
  end

  def fc
    self["FC"]
  end

  def fflags
    self["FFLAGS"]
  end

  def fcflags
    self["FCFLAGS"]
  end

  # Outputs the current compiler.
  # @return [Symbol]
  # <pre># Do something only for the system clang
  # if ENV.compiler == :clang
  #   # modify CFLAGS CXXFLAGS OBJCFLAGS OBJCXXFLAGS in one go:
  #   ENV.append_to_cflags "-I ./missing/includes"
  # end</pre>
  def compiler
    @compiler ||= if (cc = @args.cc)
      warn_about_non_apple_gcc($&) if cc =~ GNU_GCC_REGEXP
      fetch_compiler(cc, "--cc")
    elsif (cc = homebrew_cc)
      warn_about_non_apple_gcc($&) if cc =~ GNU_GCC_REGEXP
      compiler = fetch_compiler(cc, "HOMEBREW_CC")

      if @formula
        compilers = [compiler] + CompilerSelector.compilers
        compiler = CompilerSelector.select_for(@formula, compilers)
      end

      compiler
    elsif @formula
      CompilerSelector.select_for(@formula)
    else
      DevelopmentTools.default_compiler
    end
  end

  # @private
  def determine_cc
    COMPILER_SYMBOL_MAP.invert.fetch(compiler, compiler)
  end

  COMPILERS.each do |compiler|
    define_method(compiler) do
      @compiler = compiler
      self.cc  = determine_cc
      self.cxx = determine_cxx
    end
  end

  # Snow Leopard defines an NCURSES value the opposite of most distros.
  # @see https://bugs.python.org/issue6848
  # Currently only used by aalib in core.
  def ncurses_define
    append "CPPFLAGS", "-DNCURSES_OPAQUE=0"
  end

  # @private
  def userpaths!
    path = PATH.new(self["PATH"]).select do |p|
      # put Superenv.bin and opt path at the first
      p.start_with?("#{HOMEBREW_REPOSITORY}/Library/ENV", "#{HOMEBREW_PREFIX}/opt")
    end
    path.append(HOMEBREW_PREFIX/"bin") # XXX hot fix to prefer brewed stuff (e.g. python) over /usr/bin.
    path.append(self["PATH"]) # reset of self["PATH"]
    path.append(
      # user paths
      ORIGINAL_PATHS.map do |p|
        p.realpath.to_s
      rescue
        nil
      end - %w[/usr/X11/bin /opt/X11/bin],
    )
    self["PATH"] = path
  end

  def fortran
    # Ignore repeated calls to this function as it will misleadingly warn about
    # building with an alternative Fortran compiler without optimization flags,
    # despite it often being the Homebrew-provided one set up in the first call.
    return if @fortran_setup_done

    @fortran_setup_done = true

    flags = []

    if fc
      ohai "Building with an alternative Fortran compiler"
      puts "This is unsupported."
      self["F77"] ||= fc
    else
      if (gfortran = which("gfortran", (HOMEBREW_PREFIX/"bin").to_s))
        ohai "Using Homebrew-provided Fortran compiler."
      elsif (gfortran = which("gfortran", PATH.new(ORIGINAL_PATHS)))
        ohai "Using a Fortran compiler found at #{gfortran}."
      end
      if gfortran
        puts "This may be changed by setting the FC environment variable."
        self["FC"] = self["F77"] = gfortran
        flags = FC_FLAG_VARS
      end
    end

    flags.each { |key| self[key] = cflags }
    set_cpu_flags(flags)
  end

  # @private
  def effective_arch
    if @args&.build_bottle? && @args&.bottle_arch
      @args.bottle_arch.to_sym
    else
      Hardware.oldest_cpu
    end
  end

  # @private
  def gcc_version_formula(name)
    version = name[GNU_GCC_REGEXP, 1]
    gcc_version_name = "gcc@#{version}"

    gcc = Formulary.factory("gcc")
    if gcc.version_suffix == version
      gcc
    else
      Formulary.factory(gcc_version_name)
    end
  end

  # @private
  def warn_about_non_apple_gcc(name)
    begin
      gcc_formula = gcc_version_formula(name)
    rescue FormulaUnavailableError => e
      raise <<~EOS
        Homebrew GCC requested, but formula #{e.name} not found!
      EOS
    end

    return if gcc_formula.opt_prefix.exist?

    raise <<~EOS
      The requested Homebrew GCC was not installed. You must:
        brew install #{gcc_formula.full_name}
    EOS
  end

  def permit_arch_flags; end

  # A no-op until we enable this by default again (which we may never do).
  def permit_weak_imports; end

  # @private
  def compiler_any_clang?(cc = compiler)
    %w[clang llvm_clang].include?(cc.to_s)
  end

  private

  def cc=(val)
    self["CC"] = self["OBJC"] = val.to_s
  end

  def cxx=(val)
    self["CXX"] = self["OBJCXX"] = val.to_s
  end

  def homebrew_cc
    self["HOMEBREW_CC"]
  end

  def fetch_compiler(value, source)
    COMPILER_SYMBOL_MAP.fetch(value) do |other|
      case other
      when GNU_GCC_REGEXP
        other
      else
        raise "Invalid value for #{source}: #{other}"
      end
    end
  end

  def check_for_compiler_universal_support
    return unless homebrew_cc.match?(GNU_GCC_REGEXP)

    raise "Non-Apple GCC can't build universal binaries"
  end
end

require "extend/os/extend/ENV/shared"
