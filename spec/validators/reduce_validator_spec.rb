# encoding: UTF-8

require "rails_helper"

RSpec.describe ReduceValidator do
  let(:model) do
    Class.new do
      include ActiveModel::Model

      attr_accessor :name, :code

      validates :name, presence: true, length: {minimum: 2}, reduce: true
      validates :code, presence: true, length: {minimum: 2}

      def self.name = "Thing"
    end
  end

  it "keeps only the first error on a reduced attribute" do
    thing = model.new(name: "", code: "")

    thing.valid?

    expect(thing.errors.full_messages_for(:name)).to eq(["Name can't be blank"])
    expect(thing.errors.full_messages_for(:code).size).to eq(2)
  end

  it "adds nothing when the attribute is valid" do
    thing = model.new(name: "ok", code: "ok")

    expect(thing).to be_valid
  end
end
