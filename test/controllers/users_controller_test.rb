require 'test_helper'

class UsersControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test 'current returns the signed in user' do
    user = User.create!(email: 'current@example.com', password: 'password123')
    sign_in user
    get current_users_path, as: :json
    assert_response :success
    assert_equal user.id, response.parsed_body.fetch('user').fetch('id')
  end

  test 'current requires authentication' do
    get current_users_path, as: :json
    assert_response :unauthorized
  end
end
