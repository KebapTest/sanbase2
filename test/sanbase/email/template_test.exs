defmodule Sanbase.Email.TemplateTest do
  use Sanbase.DataCase, async: true

  alias Sanbase.Email.Template

  describe "#choose_login_template when it is user's first login" do
    test "when user comes from Sheets" do
      assert Template.choose_login_template("https://sheets.santiment.net", first_login?: true) ==
               "sheets-sign-up"
    end

    test "when user comes from Neuro" do
      assert Template.choose_login_template("https://neuro.santiment.net", first_login?: true) ==
               "neuro-sign-up"
    end

    test "when user comes from other place (mainly sanbase)" do
      assert Template.choose_login_template("http://example.com", first_login?: true) ==
               "sanbase-sign-up"
    end
  end

  describe "#send_login_email when it is not user's first login" do
    test "when user comes from Sheets" do
      assert Template.choose_login_template("https://sheets.santiment.net", first_login?: false) ==
               "sheets-sign-in"
    end

    test "when user comes from Neuro" do
      assert Template.choose_login_template("https://neuro.santiment.net", first_login?: false) ==
               "neuro-sign-in"
    end

    test "when user comes from other place (mainly sanbase)" do
      assert Template.choose_login_template("http://example.com", first_login?: false) ==
               "sanbase-sign-in"
    end
  end
end
