require 'spec_helper'

describe KeyTransformer do
  let(:camel_hash) { { 'anAttribute' => { 'nestedAttribute' => [ { 'nestedInAnArray' => 'good enough' } ] } } }
  let(:upper_camel_hash) { { 'AnAttribute' => { 'NestedAttribute' => [ { 'NestedInAnArray' => 'good enough' } ] } } }
  let(:underscore_hash) { { 'an_attribute' => { 'nested_attribute' => [ { 'nested_in_an_array' => 'good enough' } ] } } }

  describe ".underscore_keys" do
    it "should transform camelized keys to underscored" do
      KeyTransformer.underscore_keys(camel_hash).should == underscore_hash
    end

    it "should be able to handle several transforms" do
      KeyTransformer.underscore_keys(KeyTransformer.camelize_keys(KeyTransformer.underscore_keys(camel_hash))).should == underscore_hash
    end
  end

  describe ".camelize_keys" do
    it "should transform underscored keys to camelCase" do
      KeyTransformer.camelize_keys(underscore_hash).should == camel_hash
    end

    it "should end up in the same place, however the keys started" do 
      KeyTransformer.camelize_keys(underscore_hash).should == KeyTransformer.camelize_keys(camel_hash)
    end

    it "should transformer keys to lower-camel if passed :lower" do
      KeyTransformer.camelize_keys(underscore_hash, :lower).should == camel_hash
    end

    it "should transformer keys to upper-camel if passed :upper" do
      KeyTransformer.camelize_keys(underscore_hash, :upper).should == upper_camel_hash
    end
  end

  describe ".transform_keys" do
    it "should transform keys in an arbitrary way" do
      KeyTransformer.transform_keys(underscore_hash, Proc.new { |key| 'x' }).should == { 'x' => { 'x' => [ { 'x' => 'good enough' } ] } }
    end
  end

end
