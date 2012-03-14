# encoding: utf-8

require File.expand_path(File.dirname(__FILE__) + '/spec_helper')

require 'json'

describe Base do
  describe "the Base class" do
    after do
      load 'lib/well_rested/base.rb'  # reload class to undo any class-level changes
    end
    
    describe "define_schema" do
      class ParentRes < Base
        define_schema :name
      end

      class ChildRes < ParentRes
      end

      class ChildChange < ParentRes
        define_schema :foo
      end

      it "should be inherited by a child class" do
        ChildRes.schema.should == ParentRes.schema
      end

      it "should not be changed in the parent when changed in the child" do
        ChildChange.schema.keys.should == ['foo']
        ParentRes.schema.keys.should include 'name'
        ParentRes.schema.keys.should_not include 'foo'
      end
    end
    
    describe ".path" do
      subject { Base.path }
      it { should be_blank }
    end
    
    describe ".server" do
      subject { Base.server }
      it { should be_blank }
    end

    it "should perform variable substitution on the path" do
      Base.path = '/test/:var/bar/:kee'
      Base.fill_path(:var => 'foo', :kee => 'mah').should == '/test/foo/bar/mah'
    end

    it "should have a default initializer" do
      Base.new.should be_a Base
    end
  end

  class SimpleResource < Base
    define_schema :id
  end

  class TestResource < Base
    define_schema :id, :test_resource
  end

  class ResourceWithDefaults < Base
    define_schema :id, :attr => 'default value'
  end

  describe "an instance of the Base class" do
    before { @res = SimpleResource.new }
    subject { @res }
    
    it { should be_valid }
    it { should respond_to(:id) }

    describe ".new_record" do
      it "should be false when an object comes from the API" 
      it "should be true when an object is created with .new and has no ID"
    end

    describe ".attributes" do
      subject { res.attributes }
      
      context "when initialized with a default constructor and no schema" do
        let(:res) { Base.new } 
        it { should == {} }
      end
      
      context "when initialized with an attribute not defined in the schema" do
        context "with a string key" do
          let(:res) { Base.new('my_at' => 'val') }
          it { should == { 'my_at' => 'val' } }
          it { should include :my_at }
          it { should include 'my_at' }
          it "should produce the same value for string and equivalent symbol keys" do
            res.attributes[:my_at] == res.attributes['my_at']
          end
        end
        
        context "with a symbol key" do
          let(:res) { Base.new(:my_at => 'val') }
          it { should == { 'my_at' => 'val' } }
          it { should include :my_at }
          it { should include 'my_at' }
          it "should produce the same value for string and equivalent symbol keys" do
            res.attributes[:my_at] == res.attributes['my_at']
          end          
        end 
      end
    end

    # attributes_for_api should be the same as attributes, except that it filters elements
    # not in the schema when the schema is defined
    # TODO: find a way to specify that all tests for attributes apply to attributes for API
    # except when schema is defined
    describe ".attributes_for_api" do
      subject { res.attributes_for_api }
      
      context "when initialized with default constructor and no schema" do
        let(:res) { Base.new }
        it { should == {} }
        
        context "when an attribute is added" do
          before { res.attributes[:foo] = 'bar' }
          it "should include them" do
            res.attributes_for_api.keys.should include 'foo'
          end
        end
      end
      
      context "when initialized with a default constructor with a schema" do
        let(:res) { SimpleResource.new }
        
        context "when an attribute not in the schema is added" do
          before { res.attributes[:foo] = 'bar' }
          it "should not include them" do
            res.attributes_for_api.keys.should_not include 'foo'
          end
        end
      end
      
      context "when initialized with an attribute and no schema" do
        let(:res) { Base.new :x => 'y' }
        it { should == {'x' => 'y'} }
      end
      
      context "when initialized with a nested object defined in the schema" do
        let(:res) { TestResource.new(:id => 1, :test_resource => TestResource.new(:id => 2)) }

        it "should turn objects back into hashes" do
          res.test_resource.should be_a TestResource  # sanity check
          res.attributes_for_api[:test_resource].should be_a Hash
        end
      end

      context "when the schema includes default values for attributes not set on the resource" do
        before { @res = ResourceWithDefaults.new }
        it "should include the default values" do
          @res.attributes_for_api[:id].should be_nil
          @res.attributes_for_api[:attr].should == 'default value'
        end
      end
    end

    describe ".new_from_api" do
      it "should call load_from_api" do
        mock = double()
        mock.should_receive(:load_from_api)
        Base.stub!(:new).and_return(mock)
        Base.new_from_api({})
      end

      it "should set new_record to false" do
        b = Base.new_from_api({})
        b.new_record.should == false
      end
    end

    describe ".load" do
      it "should replace existing attributes" do
        obj = Base.new :foo => 'bar'
        obj.attributes[:foo].should == 'bar'   # 
        obj.load('fum' => 'baz')
        obj.attributes[:fum].should == 'baz'
        obj.attributes.should_not include 'foo'
      end
    end

    # It is not new if it was loaded from the API. 
    # If it was loaded locally but has an ID defined, but default it is not considered new either.
    # This is to support the case where an update call is made by calling Resource.new followed by @api.save(res).
    # For Rails, we need .new? to return false when rendering a form with an error or else the form will not have _method => PUT.
    describe ".new?" do
      before { @obj = Base.new }
      subject { @obj.new? }
      context "when called with from_api as true and without an ID" do
        before { @obj.load({:x => 1}, true) }
        it { should be_false }
      end
      context "when called with from_api as true and with an ID" do
        before { @obj.load({:id => 1}, true) }
        it { should be_false }
      end
      context "when called with from_api as false and with an ID" do
        before { @obj.load({:id => 1}, false) }
        it { should be_false }
      end
      # Only case where it is considered new by default.
      context "when called with from_api as false and without an ID" do
        before { @obj.load({:x => 1}, false) }
        it { should be_true }
      end
    end

    describe ".load_for_api" do
      it "should call .load with from_api true" do
        obj = Base.new
        attrs = {:a => 'b'}
        obj.should_receive(:load).with(attrs, true)
        obj.load_from_api(attrs)
      end
    end

    describe ".path_parameters" do
      it "should fetch the same thing as attributes_for_api (unless it gets overridden)" do
        @res.path_parameters.should == @res.attributes_for_api
      end
    end

    describe "hash to object conversion" do
      class FooBar < Base
        define_schema :name
      end

      before do
        attributes = {
          :name => 'A Base',
          :parent_resource => {
            :name => 'A Sub-base',
            :parent_resource => { :name => 'grandchild' },
            :parent_resources => [
              { :name => 'First sub class in array' },
              { :name => 'Second sub class in array' },
            ],
          },
          :foo_bar => {
            :name => 'This is a foobar'
          },
          :foo_bars => [
            { :name => 'foo' },
            { :name => 'bar' }
          ],
          :just_a_hash => {
            :one => 'a',
            :two => 'b',
          }
        }
        class ParentResource < Base
          define_schema :name, :foo_bar, :just_a_hash, :parent_resource, :parent_resources
        end
        @obj = ParentResource.new_from_api(attributes) #, @api)
      end

      it "should leave regular hashes alone" do
        @obj.just_a_hash.should == { 'one' => 'a', 'two' => 'b' }
      end

      it "should convert an attributes hash into an object" do 
        @obj.foo_bar.should be_a FooBar
      end

      it "should convert an array of attribute hashes into an array of objects" do
        @obj.foo_bars.each do |b|
          b.should be_a FooBar
        end
      end

      it "should work with multi-word classes" do
        @obj.parent_resource.should be_a ParentResource
      end

      it "should work with subclasses" do
        @obj.parent_resource.parent_resource.should be_a ParentResource
      end

      it "should work with arrays of subclasses" do
        @obj.parent_resource.parent_resources.each do |s|
          s.should be_a ParentResource
        end
      end
    end

    describe '.to_param' do
      context "when an ID is set" do
        before { @res = TestResource.new :id => 4 }

        it "should equal a string representation of the ID" do
          @res.to_param.should == '4'
        end
      end

      context "when no ID is set" do
        before { @res = TestResource.new }
        subject { @res.to_param }
        it { should be_nil }
      end
    end

    describe ".to_json" do
      subject { res.to_json }
      
      context "when initialized with default constructor and no schema" do
        let(:res) { Base.new }
        it { should == { :base => {} }.to_json }
      end
      
      context "when initialized with an attribute not in the schema using a symbol key" do
        let(:res) { Base.new(:my_at => 'val') }
      
        it { should == {:base => {:my_at => 'val'}}.to_json }
      end
      
    end

    describe "attribute getter and setters" do
      context "with no schema defined" do
        before { @res = Base.new(:my_at => 'val') }
        subject { @res }

        it "should have a getter for the attribute" do
          @res.my_at.should == 'val'
        end

        it "should have a setter for the attribute" do
          @res.my_at = 'foo'
          @res.my_at.should == 'foo'
        end
      end
      
      context "with a schema" do   
        before { @res = ResourceWithDefaults.new(:other => 'zee') }
        
        it "should have an accessor for an attribute in the schema" do
          expect { @res.attr }.should_not raise_error
        end
        
        it "should have a setter for an attribute in the schema" do
          expect { @res.attr = nil }.should_not raise_error
        end
       
        it "should have an accessor for an attribute not in the schema" do
          expect { @res.other }.should_not raise_error 
        end
        
        it "should have a setter for an attribute not in the schema" do
          expect { @res.other = nil }.should_not raise_error 
        end
      end
    end

    describe ".==" do
      it "should return false when applied to objects that do not respond to attributes" do
        FooBar.new.should_not == "a string"
      end

      context "two objects of different classes have the same attributes" do
        before do
          klass1 = Class.new(FooBar)
          klass2 = Class.new(FooBar)
          @res  = klass1.new('first' => 77, :alejandro => 'fork')
          @res2 = klass2.new(@res.attributes)
        end

        it "should return true when applied to an object with the same attributes" do
          @res.should == @res2
          @res2.should == @res
        end
      end
    end
  end
end

