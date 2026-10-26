require "rails_helper"
require "csv"

RSpec.describe Validators::RegexValidator do
  subject(:processor) { described_class.new(validation) }

  let(:column) { Column.new(name: "reference_code", position: 0) }
  let(:validation) { Validation.new(column: column, input_json: { "pattern" => pattern }) }
  let(:pattern) { '\A[A-Z]{2}-[0-9]{4}\z' }
  let(:row) { CSV::Row.new(["other", "reference_code"], ["AB-1234", value]) }

  describe "#validate" do
    {
      "matching" => ["CD-5678", true],
      "nonmatching" => ["invalid", false],
      "partially matching" => ["prefix CD-5678 suffix", false],
      "padded" => [" CD-5678 ", false],
      "NULL" => [nil, true],
      "empty" => ["", true],
      "whitespace-only" => [" \t\n", true],
    }.each do |description, (field, accepted)|
      context "with a #{description} field" do
        let(:value) { field }

        it "#{accepted ? 'accepts' : 'rejects'} the configured field by header" do
          expect(processor.validate(row)).to be accepted
        end
      end
    end

    it "skips a missing header as a blank value" do
      expect(processor.validate(CSV::Row.new(["other"], ["invalid"]))).to be true
    end

    context "with an unanchored pattern" do
      let(:pattern) { "[A-Z]{2}-[0-9]{4}" }
      let(:value) { "prefix CD-5678 suffix" }

      it "allows substring matches as configured" do
        expect(processor.validate(row)).to be true
      end
    end

    context "with Unicode character classes" do
      let(:pattern) { '\A\p{L}+\z' }
      let(:value) { "\u00e9\u754c" }

      it "matches multibyte characters without changing the row" do
        original = row.to_h

        expect(processor.validate(row)).to be true
        expect(row.to_h).to eq(original)
      end
    end

    context "when matching times out" do
      let(:value) { "CD-5678" }

      it "rejects the row without propagating the timeout" do
        compiled_regex = processor.regex
        allow(processor).to receive(:regex).and_return(compiled_regex)
        allow(compiled_regex).to receive(:match?).with(value).and_raise(Regexp::TimeoutError)

        expect(processor.validate(row)).to be false
      end
    end
  end

  it "limits each match to 50 milliseconds independently of the global timeout" do
    expect(processor.regex.timeout).to eq(0.05)
  end
end
