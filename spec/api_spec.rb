# encoding: utf-8

require File.expand_path(File.dirname(__FILE__) + '/spec_helper')

describe API do
  before(:each) do
    @account_class = Class.new(Base) do
      self.path = '/accounts'
    end
    @user_class = Class.new(Base) do
      self.path = '/accounts/:account_id/users'
    end
  end

  before do
    @api = mock_api 
    FakeWeb.register_uri(:get, %r|/accounts$|, :body => '[{}]')
    FakeWeb.register_uri(:get, %r|/accounts/1$|, :body => '{}')
    FakeWeb.register_uri(:get, %r|/accounts/1/users|, :body => '[{}]', 'x_record_count' => '2')
    FakeWeb.register_uri(:get, %r|/accounts/1/users/1|, :body => '{}')
  end

  after do
    FakeWeb.clean_registry
  end

  describe "class methods" do
    describe ".request_headers" do
      subject { API.request_headers }
      it { should be_a Hash }
    end
    
    describe '.fill_path' do
      it "should return the path with filled parameters" do
        API.fill_path('/something/:that/has/:parameters', :that => 'foo', :parameters => 'bar').should == '/something/foo/has/bar'
      end

      it "should raise an exception if there are unmatched parameters" do
        expect { API.fill_path('/something/:that/lacks/:parameters', :that => 'foo') }.should raise_error ArgumentError
      end

      it "should raise an exception if there is a blank param" do
        expect { API.fill_path('/something/:that/lacks/parameters', :that => '') }.should raise_error ArgumentError
      end
    end
  end

  describe '.request_headers' do
    subject { @api.request_headers }
    it { should be_a Hash }
  end

  describe ".url_for" do
    it "should substitute path params" do
      @api.url_for(@user_class, :account_id => 1).should match /accounts\/1\/users/
    end

    it "should append query params when passed a hash" do
      @api.url_for(@account_class, {}, :count => 4).should match /accounts\?count=4$/
    end

    it "should append query params when passed a string" do
      @api.url_for(@account_class, '/accounts', :count => 4).should match /accounts\?count=4$/
    end

    it "should attribute-encode query params" do
      @account_class.attribute_formatter = CamelCaseFormatter.new
      @api.url_for(@account_class, '/accounts', :my_count => 4).should match /accounts\?myCount=4$/
    end

    it "should use the specified extension" do
      @account_class.extension = '.foobar'
      @api.url_for(@account_class, '/accounts', :my_count => 4).should match /accounts.foobar\?myCount=4$/
    end

    context "with auth set" do
      before do
        @api.user = 'admin'
        @api.password = 'password'
      end

      it "should generate a url with auth" do
        @api.url_for(@account_class).should match /:\/\/admin:password@/
      end
    end
  end

  describe ".default_path_parameters" do
    context "with empty initializer" do
      subject { @api.default_path_parameters }

      it { should be_empty }
    end

    context "with params in initializer" do
      before { @api = API.new(:account_id => 7, :id => 2) } 

      it "should have the passed value" do
        @api.default_path_parameters.should == { 'account_id' => 7, 'id' => 2 }
      end

      it "should use the default path params when generating URLs" do
        @api.url_for(@user_class).should =~ /accounts\/7\/users\/2/
      end
    end
  end

  describe 'API Calls' do
    describe ".request" do
      it "should issue a PUT request" do
        FakeWeb.register_uri(:put, "#{base_path}/request_put_test", :body => '')
        @api.request(Base, :put, "/request_put_test")
        FakeWeb.should have_requested(:put, "http://#{base_path}/request_put_test")
      end

      it "should issue a POST request" do
        FakeWeb.register_uri(:post, "#{base_path}/request_post_test", :body => '{}')
        @api.request(Base, :post, "/request_post_test")
        FakeWeb.should have_requested(:post, "http://#{base_path}/request_post_test")
      end

      it "should issue a GET request" do
        FakeWeb.register_uri(:get, "#{base_path}/request_get_test", :body => '{}')
        @api.request(Base, :get, "/request_get_test")
        FakeWeb.should have_requested(:get, "http://#{base_path}/request_get_test")
      end

      it "should issue a DELETE request" do
        FakeWeb.register_uri(:delete, "#{base_path}/request_del_test", :body => '')
        @api.request(Base, :delete, "/request_del_test")
        FakeWeb.should have_requested(:delete, "http://#{base_path}/request_del_test")
      end

      context "when passed a fully qualified url" do
        before { FakeWeb.register_uri(:get, "#{base_path}/request_get_url", :body => '{}') }

        it "should use it directly" do
          @api.request(Base, :get, "http://#{base_path}/request_get_url")
        end
      end

      context "when passed a relative path (beginning with a slash)" do
        before { FakeWeb.register_uri(:get, "#{base_path}/request_get_path", :body => '{}') }

        it "should fill it out" do
          @api.request(Base, :get, "/request_get_path")
        end
      end
    end

    describe '.find' do
      context "when passed a url" do
        before { 
          @path = "#{base_path}/my/weird/path"
          FakeWeb.register_uri(:get, @path, :body => '{}')
          @account = @api.find(@account_class, '/my/weird/path')
        }
        it "should use the URL" do
          FakeWeb.should have_requested(:get, "http://#{@path}")
        end

        it "should return a resource of the requested type" do
          @account.should be_an @account_class
        end

        it "should raise an exception if the server returns 404" do
          expect { @api.find(@account_class, "/notfound") }.should raise_error 
        end
      end

      context "when passed path params" do
        before { @account = @api.find(@account_class, :id => 1) }

        it "should return a resource of the requested type" do
          @account.should be_an @account_class
        end

        it "should handle query params" do
          FakeWeb.register_uri(:get, %r|/accounts\/1\?test=true|, :body => '{}')
          @api.find(@account_class, {:id => 1}, :test => 'true')
          FakeWeb.should have_requested(:get, %r|/accounts\/1\?test=true|)
        end

        it "should create the resource using new_from_api" do
          @account_class.should_receive(:new_from_api)
          @api.find(@account_class, :id => 1)
        end
      end

      context "it includes a camelized attribute name" do
        before(:each) do
          @api.client.should_receive(:get).and_return '{ "camelizedAttrName" : "value" }'
          @user = @api.find(@account_class, :id => 1)
        end

        it "should not include camelize attribute names" do
          @user.attributes.should_not include('camelizedAttrName')
        end

        it "should include decamelized attribute names" do
          @user.attributes['camelized_attr_name'].should == "value"
        end
      end

      context "when a resource is passed instead of a class and params" do
        before do
          FakeWeb.register_uri(:get, %r|/test/7/foo/4|, :body => '{}')
        end
        it "should use the path_parameters as path parameters" do
          klass = Class.new(Base) do
            self.path = '/test/:account_id/foo'
          end
          res = klass.new(:id => 4, :account_id => 7)
          @api.find(res)
          FakeWeb.should have_requested(:get, %r|/test/7/foo/4|)
        end
      end

    end

    describe '.find_many' do
      it "should allow a URL override" do
        FakeWeb.register_uri(:get, %r|\/alternate\/users\/path|, :body => '[]')
        @api.find_many(@user_class, '/alternate/users/path')
        FakeWeb.should have_requested(:get, %r|\/alternate\/users\/path|)
      end

      it "should set last_response on @api with headers" do 
        @api.last_response.should be_nil  # sanity check
        @users = @api.find_many(@user_class, :account_id => 1)
        @api.last_response.headers[:'x_record_count'].should == '2'
      end

      context "with no parameters" do
        before(:each) { @users = @api.find_many(@user_class, :account_id => 1) }

        it "should return a collection of objects of the requested type" do
          @users.should be_an Array
          @users.size.should be > 0  # sanity check
          @users.each { |a| a.should be_a @user_class }
        end
      end

      context "with parameters" do
        before { @users = @api.find_many(@user_class, {:account_id => 1}, :count => 1) }

        it "should return the number of objects requested" do
          @users.size.should == 1
        end

        it "should create the resources using new_from_api" do
          @user_class.should_receive(:new_from_api).any_number_of_times
          @api.find_many(@user_class, {:account_id => 1}, :count => 1)
        end
      end

    end

    describe ".create" do
      before do
        FakeWeb.register_uri(:post, %r||, :body => '{ "id": "test" }', :status => 200)
        @klass = Class.new(Base) { self.path = '' }
        @res = @klass.new
      end

      it "should allow a URL override" do
        FakeWeb.clean_registry
        FakeWeb.register_uri(:post, %r|/alternative/path|, :body => '{ "id": "test" }')
        @api.create(@klass, {}, '/alternative/path')
        FakeWeb.should have_requested(:post, %r|/alternative/path|)
      end

      it "should create the object using new" do
        @klass.should_receive(:new).at_least(:once).and_return(@res)
        @api.create(@klass, {})
      end

      it "should call attributes_for_api on the resource" do
        @klass.stub!(:new).and_return(@res)
        @res.should_receive(:attributes_for_api).at_least(:once).and_return({})
        @api.create(@klass)
      end
      it "should not call attributes on the resource" do 
        @klass.stub!(:new_from_api).and_return(@res)
        @res.should_not_receive(:attributes)
        @api.create(@klass)
      end

      it "should camelize keys" do
        attributes = { :underscored_key => 'foo' }
        @api.client.should_receive(:post).with(anything, {:underscoredKey => 'foo'}.to_json, anything).and_return(double(:code => 200, :body => '{}'))
        @api.create(@klass, attributes)
      end

      context "when the resource is valid" do
        before(:each) do
          @attrs = { :account_id => 1, :first_name => 'FirsTest', :last_name => 'LasTest', :email_address => 'a@b' }
          @user_class.new(@attrs).should be_valid  # sanity check that user is really valid
        end

        it "should POST to the resource path" do
          user = @api.create(@user_class, @attrs)
          user.should be_a @user_class
        end
      end

      context "when an ID is set" do
        before { @res = @klass.new(:id => 9) }

        it "should not issue a POST" do
          @api.client.stub(:put).and_return(double(:code => 200, :body => '{}'))
          @api.client.should_not_receive(:post)
          @api.save(@res)
        end

        it "should issue a PUT" do
          @api.client.should_receive(:put).and_return(double(:code => 200, :body => '{}'))
          @api.save(@res)
        end
      end

      context "when the resource is invalid" do
        it "should return false" do
          klass = Class.new(Base) do
            def valid?
              false
            end
          end
          klass.new.should_not be_valid

          @api.create(klass, {}).should == false
        end
      end

      context "when saving a new record" do
        it "should mark the record persisted after save completes" do
          @res.should be_new_record  # sanity check
          @api.save(@res)
          @res.should_not be_new_record
        end
      end

      context "when the resource is an array" do
        before do
          @klass = Class.new(Base) do
            self.path = '/array/resource'
          end
          FakeWeb.clean_registry
          FakeWeb.register_uri(:post, %r|/array\/resource$|, :body => '[{"name":"one"}, {"name":"two"}]')
        end

        it "should return an array when the resource is an array" do 
          res = @api.create(@klass)
          res.should be_an Array
          res.first.name.should == "one"
          res.last.name.should == "two"
        end
      end

    end

    describe '.save' do
      before do 
        @klass = Class.new(Base) { self.path = '' }
        @res = @klass.new(:id => 4)
      end

      it "should set the correct content-type" do
        @user = @user_class.new :first_name => 'First', :last_name => 'Last', 
          :account_id => 1, :email_address => 'user@foo', :password => 'foobar', :id => 77 

        @api.client.should_receive(:put).with(@api.url_for(@user_class, @user.attributes_for_api), 
                                              KeyTransformer.camelize_keys(@user.attributes_for_api).to_json, 
                                              @api.request_headers).and_return(double(:code => 200, :body => '{}'))
        @api.save(@user)
      end

      it "should camelize keys" do
        @res.load(:id => 4, :underscored_key => 'foo')
        @api.client.should_receive(:put).with(anything, {:id => 4, :underscoredKey => 'foo'}.to_json, anything).and_return(
          double(:code => 200, :body => '{}'))
        @api.save(@res)
      end     

      context "when attributes_for_api and path_params differ" do
        before do
          @klass = Class.new(Base) do 
            self.path = '/test/:special_attr/blah'
            define_schema :id, :special_attr
          end
          @res = @klass.new
          @res.id = 4
          @res.stub!(:attributes).and_return({:id => 4, :special_attr => 'bad' }.with_indifferent_access)
          @res.stub!(:attributes_for_api).and_return({:id => 4, :special_attr => 'bad' }.with_indifferent_access)
          @res.stub!(:path_parameters).and_return({:id => 4, :special_attr => 'good'}.with_indifferent_access)
        end

        it "should use the path_parameters for path substitution" do
          FakeWeb.register_uri(:put, %r|/test/good/blah/4$|, :body => '{}')
          #FakeWeb.should have_requested(:put, %r|/test/foo/blah/4$|)  # why doesn't this work?

          @api.save(@res)
        end

        it "should use the attributes_for_api for the payload" do
          @api.client.should_receive(:put).with(anything(), {:id => 4, :specialAttr => 'bad'}.to_json, anything()).and_return(
            double(:body => '{}', :code => 200))
          @api.save(@res)
        end
      end

      context "when save succeeds" do
        before do
          FakeWeb.register_uri(:put, %r|.*|, :body => '{"newattr":"newval"}')
          @api.save(@res)
        end

        it "should be updated in place" do
          @res.newattr.should == 'newval'
        end
      end

      context "when host returns a 422" do
        before do
          @res = @klass.new(:id => 4, :attr => 'val')
          FakeWeb.register_uri(:put, %r||, :body => '{"errors":["first"]}', :status => 422)
        end

        it "should return false" do
          ret = @api.save(@res)
          ret.should == false
        end

        it "should not modify the resource, except to add errors" do
          old_attrs = @res.attributes.clone
          ret = @api.save(@res)
          @res.attributes.should == old_attrs
          @res.errors.to_hash.should == {:base => ['first']}
        end
      end

      context "when host returns a 400" do
        before do
          @res = @klass.new(:id => 4, :attr => 'val')
          FakeWeb.register_uri(:put, %r||, :body => '', :status => 400)
        end

        it "should raise an error" do
          expect { @api.save(@res) }.should raise_error RestClient::BadRequest
        end
      end

      context "when no ID is set" do
        before { @res = @klass.new }
        it "should issue a POST instead of a PUT" do
          FakeWeb.register_uri(:post, %r||, :body => '{}')
          @api.save(@res)
        end
      end

      context "when the resource is invalid" do
        it "should return false" do
          klass = Class.new(Base) do
            self.path = ''
          end
          r = klass.new :id => 1
          r.should_receive('valid?').and_return(false)
          @api.client.stub!(:put).and_return('{}')
          @api.save(r).should == false
        end
      end
    end

    describe ".delete" do
      context "when called on a class" do
        it "should issue a delete to the specified ID" do
          attrs = { :account_id => 1, :id => 7 }
          FakeWeb.register_uri(:delete, @api.url_for(@user_class, attrs), :status => 200, :body => '')
          @api.delete(@user_class, attrs)
          FakeWeb.should have_requested(:delete, @api.url_for(@user_class, attrs))
        end

        it "should allow a URL override" do
          FakeWeb.register_uri(:delete, %r|/alternate/delete/path|, :status => 200, :body => '')
          @api.delete(@user_class, '/alternate/delete/path')
          FakeWeb.should have_requested(:delete, %r|/alternate/delete/path|)
        end
      end
      context "when called on a resource" do
        before { @res = @user_class.new(:account_id => 1, :id => 7) }

        it "should DELETE on the resource's url" do
          FakeWeb.register_uri(:delete, @api.url_for(@user_class, @res.attributes), :status => 200, :body => '')
          @api.delete(@res)
          FakeWeb.should have_requested(:delete, @api.url_for(@user_class, @res.attributes))
        end
      end
    end

    describe ".get" do
      context "when the response is an XML array" do
        before do
          FakeWeb.register_uri(:get, %r|/array\/resource$|, :body => '<?xml version="1.0" encoding="UTF-8"?><hash></hash>')
          #@response = @api.get("#{base_path}/array/resource", XMLFormatter.new)
        end
        it "should return an array" do
          pending
          @response.should be_an Array
        end
      end

      context "when the response is a json array" do
        before do
          FakeWeb.register_uri(:get, %r|/array\/resource$|, :body => '[{"name":"one"}, {"name":"two"}]')
          @response = @api.get("#{base_path}/array/resource")
        end
        it "should return an array" do
          @response.should be_an Array
        end
      end

      context "when the response is a hash" do
        before do
          FakeWeb.register_uri(:get, %r|/hash\/resource$|, :body => '{"name":"one"}')
          @response = @api.get("#{base_path}/hash/resource")
        end
        it "should return a hash" do
          @response.should be_a Hash
        end
      end

      # TODO: Make this format-agnostic
      context "when the response isn't valid JSON" do
        before { FakeWeb.register_uri(:get, %r|/invalid/json$|, :body => 'bogus')  }
        context "we're expecting json" do
          it "should raise an error" do
            expect { @api.get("#{base_path}/invalid/json") }.should raise_error
          end
        end
        context "we're not expecting json" do
          it "should return the string" do
            @api.get("#{base_path}/invalid/json", false).should == 'bogus'
          end
        end
      end
    end

    describe ".post" do
      # TODO: Make this format-agnostic
      context "when parsing JSON" do
        it "should issue a post to the given URL" do
          FakeWeb.register_uri(:post, %r|/custom/post/url|, :body => '{}')
          res = @api.post("#{base_path}/custom/post/url", 'asdf')
          FakeWeb.should have_requested(:post, %r|/custom/post/url|)
        end

        it "should return a hash" do
          FakeWeb.register_uri(:post, %r|/custom/post/url|, :body => '{}')
          res = @api.post("#{base_path}/custom/post/url", 'asdf')
          res.should == {}
        end
      end

      # TODO: Make this format-agnostic
      context "When not parsing JSON" do
        it "should return a string" do
          FakeWeb.register_uri(:post, %r|/custom/post/url|, :body => '{}')
          res = @api.post("#{base_path}/custom/post/url", 'asdf', false)
          res.should == '{}'
        end
      end
    end

    describe ".put" do
      it "should issue a PUT to the given URL" do
        FakeWeb.register_uri(:put, %r|/custom/put/url|, :body => '{}')
        @api.put("#{base_path}/custom/put/url", [{:a => :b}, {:b => :c}])
      end

      it "should raise an error if we get a 400" do
        FakeWeb.register_uri(:put, %r|/custom/put/url|, :status => 400, :body => '{}')
        expect { @api.put("#{base_path}/custom/put/url", [{:a => :b}, {:b => :c}]) }.should raise_error RestClient::BadRequest
      end

      context "when the server returns a list of resources" do
        before { FakeWeb.register_uri(:put, %r|/custom/put/url|, :status => 200, :body => '[{"a":"b"}]') }
        it "should return an array of hashes" do
          ar = @api.put("#{base_path}/custom/put/url", {})
          ar.should be_an Array
        end
      end

      context "when the server returns a single resource" do
        before { FakeWeb.register_uri(:put, %r|/custom/put/url|, :status => 200, :body => '{"a":"b"}') }
        it "should return an array of hashes" do
          ar = @api.put("#{base_path}/custom/put/url", {})
          ar.should be_a Hash
        end
      end

      context "when the server returns an empty response" do
        before { FakeWeb.register_uri(:put, %r|/custom/put/url|, :status => 200, :body => '') }
        it "should return an empty string" do
          ar = @api.put("#{base_path}/custom/put/url", {})
          ar.should == ""
        end
      end

      context "when passed :json => false" do
        before { FakeWeb.register_uri(:put, %r|/custom/put/url|, :status => 200, :body => '{"a":"b"}') }
        it "should return a string" do
          ar = @api.put("#{base_path}/custom/put/url", {}, :json => false)
          ar.should be_a String
        end
      end
    end
  end
end

