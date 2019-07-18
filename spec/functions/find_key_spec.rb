require 'spec_helper'

describe 'find_key' do
  it { is_expected.not_to eq(nil) }
  it { is_expected.to run.with_params.and_raise_error(ArgumentError, %r{expects 2 arguments}i) }

  it { is_expected.to run.with_params(1, 2, 3).and_raise_error(ArgumentError, %r{expects 2 arguments}i) }
  it { is_expected.to run.with_params(1, '').and_raise_error(ArgumentError, %r{expects a Hash value}i) }

  it { is_expected.to run.with_params({}, 'foobar').and_return(nil) }

  it do
    is_expected.to run.with_params(
      { 'foo' => 'bar' }, 'foo'
    ).and_return('bar')
  end

  describe 'should search nested hashes' do
    it do
      is_expected.to run.with_params(
        { 'foo' => { 'bar' => 'nested' } }, 'bar'
      ).and_return('nested')
    end
  end
  describe 'should loop nested hashes' do
    it do
      is_expected.to run.with_params(
        {
          'foo' => {},
          'bar' => {
            'y' => '13',
            'nest' => {
              'more' => 'nesting',
              'woopy' => 'looped'
            }
          }
        },
        'woopy'
      ).and_return('looped')
    end
  end
  describe 'finds nil' do
    it do
      is_expected.to run.with_params(
        {
          'foo' => {},
          'bar' => {
            'a' => 'b',
            'c' => 'notnil',
            'd' => 'e'
          },
          'c' => nil
        },
        'c'
      ).and_return(nil)
    end
  end
end
