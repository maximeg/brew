# frozen_string_literal: true

require "cli/args"
require "requirements/java_requirement"
require "fileutils"

describe JavaRequirement do
  subject { described_class.new(%w[1.8]) }

  let(:java_home) { mktmpdir }

  let(:args) { Homebrew::CLI::Args.new }

  before do
    FileUtils.mkdir java_home/"bin"
    FileUtils.touch java_home/"bin/java"
    allow(subject).to receive(:preferred_java).and_return(java_home/"bin/java")
  end

  specify "Apple Java environment" do
    expect(subject).to be_satisfied(args: args)

    expect(ENV).to receive(:prepend_path)
    expect(ENV).to receive(:append_to_cflags)

    subject.modify_build_environment(args: args)
    expect(ENV["JAVA_HOME"]).to eq(java_home.to_s)
  end

  specify "Oracle Java environment" do
    expect(subject).to be_satisfied(args: args)

    FileUtils.mkdir java_home/"include"
    expect(ENV).to receive(:prepend_path)
    expect(ENV).to receive(:append_to_cflags).twice

    subject.modify_build_environment(args: args)
    expect(ENV["JAVA_HOME"]).to eq(java_home.to_s)
  end
end
