# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EasyTalk::ActiveModelType do
  before do
    profile_class = Class.new do
      include EasyTalk::Schema
    end
    stub_const('ActiveModelTypeProfile', profile_class)
    ActiveModelTypeProfile.define_schema do
      property :title, String
    end

    settings_class = Class.new do
      include EasyTalk::Schema
    end
    stub_const('ActiveModelTypeSettings', settings_class)
    ActiveModelTypeSettings.define_schema do
      property :name, String
      property :age, Integer
      property :active, T::Boolean
      property :scores, T::Array[Integer], optional: true
      property :profile, ActiveModelTypeProfile, optional: true
    end
  end

  let(:type) { described_class.new(ActiveModelTypeSettings) }

  it 'casts primitives from strings' do
    result = type.cast('name' => 123, 'age' => '42', 'active' => 'false')

    expect(result).to be_a(ActiveModelTypeSettings)
    expect(result.name).to eq('123')
    expect(result.age).to eq(42)
    expect(result.active).to be(false)
  end

  it 'casts typed arrays' do
    result = type.cast('scores' => ['1', 2, '3'])

    expect(result.scores).to eq([1, 2, 3])
  end

  it 'casts nested schemas' do
    result = type.cast('profile' => { 'title' => 'Captain' })

    expect(result.profile).to be_a(ActiveModelTypeProfile)
    expect(result.profile.title).to eq('Captain')
  end

  it 'accepts JSON strings' do
    result = type.cast('{"name":"Ada","age":"7","active":"true"}')

    expect(result.name).to eq('Ada')
    expect(result.age).to eq(7)
    expect(result.active).to be(true)
  end
end
