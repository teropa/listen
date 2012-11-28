require 'spec_helper'

describe Listen::Adapters::Java do
  if java? && Listen::Adapters::Java.usable?
    it "is usable on Java" do
      described_class.should be_usable
    end

    it_should_behave_like 'a filesystem adapter'
    it_should_behave_like 'an adapter that call properly listener#on_change'
  end

  unless java?
    it "isn't usable outside Java" do
      described_class.should_not be_usable
    end
  end

end
