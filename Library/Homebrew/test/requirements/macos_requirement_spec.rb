# frozen_string_literal: true

require "cli/args"
require "requirements/macos_requirement"

describe MacOSRequirement do
  subject(:requirement) { described_class.new }

  describe "#satisfied?" do
    let(:args) { Homebrew::CLI::Args.new }

    it "returns true on macOS" do
      expect(requirement.satisfied?(args: args)).to eq OS.mac?
    end

    it "supports version symbols", :needs_macos do
      requirement = described_class.new([MacOS.version.to_sym])
      expect(requirement).to be_satisfied(args: args)
    end

    it "supports maximum versions", :needs_macos do
      requirement = described_class.new([:catalina], comparator: "<=")
      expect(requirement.satisfied?(args: args)).to eq MacOS.version <= :catalina
    end
  end
end
