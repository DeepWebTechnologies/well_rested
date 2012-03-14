# encoding: utf-8

require File.expand_path(File.dirname(__FILE__) + '/spec_helper')

describe Utils do
  class Resource < Base
    define_schema :name, :resource, :resources
  end

  describe ".objects_to_attributes" do
    before do
      @res = Resource.new(:name => 'Parent', 
        :resource => Resource.new(:name => 'First Child'),
        :resources => [
          Resource.new(:name => 'First List Child'),
          Resource.new(:name => 'Second List Child', :resource => Resource.new(:name => 'Grand Child'), :resources => [Resource.new(:name => 'Resource List Grandchild')])
        ]
      )

      @attrs = Utils.objects_to_attributes(@res)
    end
  
    subject { @attrs }

    it { should be_a Hash }

    it "should turn a child resource into a hash" do
      @attrs['resource'].should be_a Hash
      @attrs['resource']['name'].should == 'First Child'
    end

    it "should turn a child list into an array of hashes" do 
      @attrs['resources'].should be_an Array
      @attrs['resources'].each { |r| r.should be_a Hash }
    end
  end
end
