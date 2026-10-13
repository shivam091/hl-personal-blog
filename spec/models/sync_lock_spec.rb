# encoding: UTF-8

require "rails_helper"

RSpec.describe SyncLock do
  it "runs the block and lets the lock go afterwards, even when it raises" do
    expect(described_class.hold("a") { nil }).to be_truthy
    expect { described_class.hold("a") { raise "boom" } }.to raise_error("boom")
    expect(described_class.count).to eq(0)
  end

  it "skips the block while the lock is held" do
    described_class.hold("a") do
      expect(described_class.hold("a") { :inner }).to be_falsy
      expect(described_class.hold("b") { :other }).to be_truthy
    end
  end

  it "takes over a lock left behind by a process that died" do
    described_class.collection.insert_one(_id: "a", expires_at: 1.minute.ago)

    expect(described_class.hold("a") { :done }).to be_truthy
  end

  it "leaves alone a lock another run took over after this one outlived it" do
    described_class.hold("a") do
      described_class.where(_id: "a").update_all(expires_at: 1.minute.ago)
      expect(described_class.send(:acquire, "a", "later run")).to be_truthy
    end

    expect(described_class.where(_id: "a", token: "later run").count).to eq(1)
  end
end
