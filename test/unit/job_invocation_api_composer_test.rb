require 'test_plugin_helper'

describe JobInvocationApiComposer do
  before do
    permission1 = FactoryGirl.create(:permission, :name => 'view_job_templates', :resource_type => 'JobTemplate')
    permission2 = Permission.find_by_name('view_bookmarks')
    permission3 = Permission.find_by_name('view_hosts')
    filter1 = FactoryGirl.build(:filter, :permissions => [permission1], :search => 'name ~ testing*')
    filter2 = FactoryGirl.build(:filter, :permissions => [permission2])
    filter3 = FactoryGirl.build(:filter, :permissions => [permission3])
    filter1.save
    filter2.save
    filter3.save
    role = FactoryGirl.build(:role)
    role.filters = filter1, filter2, filter3
    role.save
    User.current = FactoryGirl.build(:user)
    User.current.roles<< role
    User.current.save
  end

  let(:testing_job_template_1) { FactoryGirl.create(:job_template, :job_name => 'testing_job_template_1', :name => 'testing1', :provider_type => 'Ssh') }

  let(:input1) { FactoryGirl.create(:template_input, :template => testing_job_template_1, :input_type => 'user', :required => true) }
  let(:input2) { FactoryGirl.create(:template_input, :template => testing_job_template_1, :input_type => 'user') }

  let(:bookmark) { bookmarks(:one) }
  let(:providers_params) { { :providers => { :ansible => ansible_params, :ssh => ssh_params, :mcollective => mcollective_params } } }

  context 'composer' do
    it "creates invocation with a bookmark" do
      params = {:job_name => testing_job_template_1.job_name,
                :template_id => testing_job_template_1.id,
                :targeting_type => "static_query",
                :bookmark_id => bookmark.id}
      ji = JobInvocation.new

      composer = JobInvocationApiComposer.new(ji, User.current, params)
      assert composer.save!
      assert_equal bookmark, ji.targeting.bookmark
      assert_equal ji.targeting.user, User.current
      refute_empty ji.template_invocations
    end

    it "creates invocation with a search query" do
      params = {:job_name => testing_job_template_1.job_name,
                :template_id => testing_job_template_1.id,
                :targeting_type => "static_query",
                :search_query => "some hosts"}
      ji = JobInvocation.new

      composer = JobInvocationApiComposer.new(ji, User.current, params)
      assert composer.save!
      assert_equal "some hosts", ji.targeting.search_query
      refute_empty ji.template_invocations
    end

    it "creates invocation with inputs" do
      params = {:job_name => testing_job_template_1.job_name,
                :template_id => testing_job_template_1.id,
                :targeting_type => "static_query",
                :search_query => "some hosts",
                :inputs => [{:name => input1.name, :value => "some_value"}]}
      ji = JobInvocation.new

      composer = JobInvocationApiComposer.new(ji, User.current, params)
      assert composer.save!
      assert_equal 1, ji.template_invocations.first.input_values.count
    end

    it "handles errors on invalid targeting" do
      params = {:job_name => testing_job_template_1.job_name,
                :template_id => testing_job_template_1.id,
                :search_query => "some hosts",
                :inputs => [{:name => input1.name, :value => "some_value"}]}
      ji = JobInvocation.new

      composer = JobInvocationApiComposer.new(ji, User.current, params)
      assert_raises(ActiveRecord::RecordNotSaved) do
        composer.save!
      end
    end

    it "handles errors with both bookmark and search_query" do
      params = {:job_name => testing_job_template_1.job_name,
                :template_id => testing_job_template_1.id,
                :targeting_type => "static_query",
                :search_query => "some hosts",
                :bookmark_id => bookmark.id,
                :inputs => [{:name => input1.name, :value => "some_value"}]}
      ji = JobInvocation.new

      assert_raises(Foreman::Exception) do
        JobInvocationApiComposer.new(ji, User.current, params)
      end
    end

    it "handles errors on invalid inputs" do
      params = {:job_name => testing_job_template_1.job_name,
                :template_id => testing_job_template_1.id,
                :targeting_type => "static_query",
                :search_query => "some hosts",
                :inputs => [{:name => input1.name, :value => "some_value"}, {:name => input2.name}]}
      ji = JobInvocation.new
      composer = JobInvocationApiComposer.new(ji, User.current, params)

      error = assert_raises(ActiveRecord::RecordNotSaved) do
        composer.save!
      end
      error.message.must_include "Template #{testing_job_template_1.name}: Input #{input2.name.downcase}: Value can't be blank"
    end

    it "accepts empty values for non-required inputs" do
      params = {:job_name => testing_job_template_1.job_name,
                :template_id => testing_job_template_1.id,
                :targeting_type => "static_query",
                :search_query => "some hosts",
                :inputs => [{:name => input1.name, :value => "some_value"}, {:name => input2.name, :value => ""}]}
      ji = JobInvocation.new
      composer = JobInvocationApiComposer.new(ji, User.current, params)

      composer.save!
      assert !ji.new_record?
    end

    it "handles errors on missing required inputs" do
      input1.must_be :required
      params = {:job_name => testing_job_template_1.job_name,
                :template_id => testing_job_template_1.id,
                :targeting_type => "static_query",
                :search_query => "some hosts",
                :inputs => [{:name => input2.name, :value => "some_value"}]}
      ji = JobInvocation.new
      composer = JobInvocationApiComposer.new(ji, User.current, params)

      error = assert_raises(ActiveRecord::RecordNotSaved) do
        composer.save!
      end

      error.message.must_include "Template #{testing_job_template_1.name}: Not all required inputs have values. Missing inputs: #{input1.name}"
    end
  end
end
