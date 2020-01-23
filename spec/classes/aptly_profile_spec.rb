require 'spec_helper'

describe 'aptly_profile' do
  on_supported_os.each do |os, facts|
    context "on #{os}" do
      let(:facts) { facts }
      let(:params) do
        {
          api_vhost: 'api.aptly',
        }
      end

      describe 'default' do
        it { is_expected.to contain_class('apache') }
        it { is_expected.to contain_apache__vhost('aptly') }

        it 'api not enabled' do
          is_expected.to_not contain_apache__vhost('api.aptly')
          is_expected.to_not contain_class('aptly::api')
        end
      end

      describe 'api_enabled: true' do
        let(:params) do
          super().merge(
            enable_api: true,
          )
        end

        it { is_expected.to contain_class('aptly::api') }
        it { is_expected.to contain_class('apache') }
        it { is_expected.to contain_apache__vhost('aptly') }
        it { is_expected.to contain_apache__vhost('api.aptly') }
      end

      describe 'manage_apache: false' do
        let(:params) do
          super().merge(
            manage_apache: false,
            enable_api: true,
          )
        end

        it { is_expected.to contain_class('aptly::api') }
        it 'does not include apache configuration' do
          is_expected.to_not contain_class('apache')
          is_expected.to_not contain_apache__vhost('aptly')
          is_expected.to_not contain_apache__vhost('api.aptly')
        end
      end
    end
  end
end
