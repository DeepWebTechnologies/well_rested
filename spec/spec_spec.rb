# encoding: utf-8

require File.expand_path(File.dirname(__FILE__) + '/spec_helper')

# These tests test the testing framework itself.
describe "Specs" do
  describe 'mock_api' do
    subject { mock_api }
    it { should be_an API }
  end

  describe 'base_path' do
    subject { base_path }
    it { should be_a String }
    it { should_not be_blank }
  end

end
