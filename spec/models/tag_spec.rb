# encoding: UTF-8

require "rails_helper"

RSpec.describe Tag, type: :model do
  it "requires a unique name" do
    Tag.create!(name: "css")

    expect(Tag.new(name: " ")).not_to be_valid
    expect(Tag.new(name: " css ")).not_to be_valid
    expect(Category.new(name: "css")).to be_valid
  end

  describe ".ids_by_name" do
    it "finds existing names and creates missing ones" do
      css = Tag.create!(name: "css")
      errors = []

      ids = Tag.ids_by_name(["css", " forms ", "", "forms"], errors)

      expect(ids.keys).to eq(%w[css forms])
      expect(ids["css"]).to eq(css.id)
      expect(Tag.names).to eq(%w[css forms])
      expect(errors).to be_empty
    end

    it "reports names that can't be saved and leaves them out" do
      errors = []

      ids = Category.ids_by_name(["x" * 101, "CSS"], errors)

      expect(ids.keys).to eq(%w[CSS])
      expect(errors).to eq(["Category \"#{"x" * 101}\": Name is too long (maximum is 100 characters)"])
    end

    it "uses the name a concurrent sync created first" do
      Tag.create_indexes
      winner = Tag.create!(name: "css")
      # So the lookup misses and the validation passes, as if the other sync
      # saved it between this one's lookup and insert.
      allow_any_instance_of(Mongoid::Criteria).to receive(:pluck) { [] }
      allow_any_instance_of(Tag).to receive(:valid?) { true }

      expect(Tag.ids_by_name(%w[css], [])).to eq({"css" => winner.id})
    end
  end
end
