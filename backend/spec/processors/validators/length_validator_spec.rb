require "rails_helper"
require "csv"

RSpec.describe Validators::LengthValidator do
  subject(:processor) { described_class.new(validation) }

  let(:column) { Column.new(name: "display_name", position: 0) }
  let(:parameters) { {} }
  let(:validation) { Validation.new(column: column, input_json: parameters) }
  let(:row) { CSV::Row.new(["other", "display_name"], ["unrelated", value]) }

  describe "#validate" do
    context "with a minimum only" do
      let(:parameters) { { "min" => 2 } }

      { "a" => false, "ab" => true, "abcd" => true }.each do |field, accepted|
        it "#{accepted ? 'accepts' : 'rejects'} a value of length #{field.length}" do
          row = CSV::Row.new(["other", "display_name"], ["unrelated", field])

          expect(processor.validate(row)).to be accepted
        end
      end
    end

    context "with a maximum only" do
      let(:parameters) { { "max" => 3 } }

      { "a" => true, "abc" => true, "abcd" => false }.each do |field, accepted|
        it "#{accepted ? 'accepts' : 'rejects'} a value of length #{field.length}" do
          row = CSV::Row.new(["other", "display_name"], ["unrelated", field])

          expect(processor.validate(row)).to be accepted
        end
      end
    end

    context "with equal bounds" do
      let(:parameters) { { "min" => 2, "max" => 2 } }

      { "a" => false, "ab" => true, "abc" => false }.each do |field, accepted|
        it "#{accepted ? 'accepts' : 'rejects'} a value of length #{field.length}" do
          row = CSV::Row.new(["other", "display_name"], ["unrelated", field])

          expect(processor.validate(row)).to be accepted
        end
      end
    end

    { "NULL" => nil, "empty" => "" }.each do |description, field|
      context "with a #{description} field" do
        let(:value) { field }

        it "treats the field as length zero when allowed" do
          validation.input_json = { "max" => 0 }

          expect(processor.validate(row)).to be true
        end

        it "rejects the field when the minimum is positive" do
          validation.input_json = { "min" => 1 }

          expect(processor.validate(row)).to be false
        end
      end
    end

    context "with a missing header" do
      it "treats the absent value as length zero" do
        validation.input_json = { "min" => 1 }

        expect(processor.validate(CSV::Row.new(["other"], ["unrelated"]))).to be false
      end
    end

    context "with multibyte characters" do
      let(:parameters) { { "min" => 2, "max" => 2 } }
      let(:value) { "\u00e9\u754c" }

      it "counts characters rather than bytes without changing the row" do
        original = row.to_h

        expect(processor.validate(row)).to be true
        expect(row.to_h).to eq(original)
      end
    end

    context "with whitespace" do
      let(:parameters) { { "min" => 2, "max" => 2 } }
      let(:value) { " \t" }

      it "counts whitespace without trimming it" do
        expect(processor.validate(row)).to be true
      end
    end
  end
end
