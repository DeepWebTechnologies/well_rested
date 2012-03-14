# encoding: utf-8

require File.expand_path(File.dirname(__FILE__) + '/spec_helper')

describe GenericUtils do
  it "should find a class by name string" do
    GenericUtils.get_class('Base').should == Base
  end

  it "should find a class by name symbol" do
    GenericUtils.get_class(:Base).should == Base
  end
end
