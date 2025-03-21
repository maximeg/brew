# frozen_string_literal: true

require "extend/ENV"
require "formula"
require "cli/parser"

module Homebrew
  module_function

  def sh_args
    Homebrew::CLI::Parser.new do
      usage_banner <<~EOS
        `sh` [<options>]

        Start a Homebrew build environment shell. Uses our years-battle-hardened
        Homebrew build logic to help your `./configure && make && make install`
        or even your `gem install` succeed. Especially handy if you run Homebrew
        in an Xcode-only configuration since it adds tools like `make` to your `PATH`
        which build systems would not find otherwise.
      EOS
      flag   "--env=",
             description: "Use the standard `PATH` instead of superenv's when `std` is passed."
      switch :verbose
      switch :debug
      max_named 0
    end
  end

  def sh
    args = sh_args.parse

    ENV.activate_extensions!(args: args)

    if superenv?(args: args)
      ENV.set_x11_env_if_installed
      ENV.deps = Formula.installed.select { |f| f.keg_only? && f.opt_prefix.directory? }
    end
    ENV.setup_build_environment(args: args)
    if superenv?(args: args)
      # superenv stopped adding brew's bin but generally users will want it
      ENV["PATH"] = PATH.new(ENV["PATH"]).insert(1, HOMEBREW_PREFIX/"bin")
    end
    subshell = if ENV["SHELL"].include?("zsh")
      "PS1='brew %B%F{green}%~%f%b$ ' #{ENV["SHELL"]} -d"
    else
      "PS1=\"brew \\[\\033[1;32m\\]\\w\\[\\033[0m\\]$ \" #{ENV["SHELL"]}"
    end
    ENV["VERBOSE"] = "1"
    puts <<~EOS
      Your shell has been configured to use Homebrew's build environment;
      this should help you build stuff. Notably though, the system versions of
      gem and pip will ignore our configuration and insist on using the
      environment they were built under (mostly). Sadly, scons will also
      ignore our configuration.
      When done, type `exit`.
    EOS
    $stdout.flush
    safe_system subshell
  end
end
