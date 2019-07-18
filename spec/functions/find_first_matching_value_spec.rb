# frozen_string_literal: true

require 'spec_helper'

describe 'aptly_profile::get_first_matching_value' do
  it 'does exist' do
    is_expected.not_to eq(nil)
  end

  it 'does work without argument' do
    is_expected.to run.with_params.and_return(nil)
  end

  it 'does work with nil keys and no criterium' do
    is_expected.to run.with_params(nil).and_return(nil)
  end

  it 'does work with nil keys and nil criterium' do
    is_expected.to run.with_params(nil, nil).and_return(nil)
  end

  it 'does work with "" key and no criterium' do
    is_expected.to run.with_params('').and_return(nil)
  end

  it 'does work with "" key and "" criterium' do
    is_expected.to run.with_params('', '').and_return(nil)
  end

  context 'strict is false' do
    it 'does return first element when no criteria is set' do
      is_expected.to run.with_params(
        { 'a' => { 'check' => 'mark' }, 'b' => {} }.freeze
      ).and_return('check' => 'mark')
    end

    it 'does return first element when no criteria is set and strict is explicitly set to false' do
      is_expected.to run.with_params(
        { 'a' => { 'check' => 'mark' }, 'b' => {} }.freeze,
        nil,
        false
      ).and_return('check' => 'mark')
    end

    it 'does return what matches' do
      is_expected.to run.with_params(
        { 'a' => { 'check' => 'mark' }, 'b' => { 'check' => 'this' } }.freeze,
        'check' => 'this'
      ).and_return('check' => 'this')
    end

    it 'returns nil if there are no matches' do
      is_expected.to run.with_params(
        { 'a' => { 'check' => 'mark' }, 'b' => { 'check' => 'this' } }.freeze,
        'foo' => 'bar'
      ).and_return(nil)
    end
  end

  context 'strict is true' do
    it 'does return nil when no criteria is set' do
      is_expected.to run.with_params(
        { 'a' => { 'check' => 'mark' }, 'b' => {} }.freeze,
        nil,
        true
      ).and_return(nil)
    end

    it 'does return what matches' do
      is_expected.to run.with_params(
        { 'a' => { 'check' => 'mark', 'must' => 'match' }, 'b' => { 'check' => 'this', 'must' => 'match', 'extra' => 'stuff' } }.freeze,
        { 'check' => 'this', 'must' => 'match' },
        true
      ).and_return('check' => 'this', 'must' => 'match', 'extra' => 'stuff')
    end
    it 'returns nil if there are no matches' do
      is_expected.to run.with_params(
        { 'a' => { 'check' => 'mark' }, 'b' => { 'check' => 'this' } }.freeze,
        { 'foo' => 'bar' },
        true
      ).and_return(nil)
    end
  end
end
