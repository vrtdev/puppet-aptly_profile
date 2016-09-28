require 'spec_helper'

describe 'find_key' do
  it { is_expected.not_to eq(nil) }
  it { is_expected.to run.with_params.and_raise_error(Puppet::ParseError, /wrong number of arguments/i) }

  it { is_expected.to run.with_params(1, 2, 3).and_raise_error(Puppet::ParseError, /wrong number of arguments/i) }
  it { is_expected.to run.with_params(1, '').and_raise_error(Puppet::ParseError, /unexpected argument type FixNum/i) }

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
end
