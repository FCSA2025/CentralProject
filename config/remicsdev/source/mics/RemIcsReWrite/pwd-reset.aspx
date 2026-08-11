<%@ Page Language="C#" %>
<%@ Assembly Name="System.Security, Version=4.0.0.0, Culture=neutral, PublicKeyToken=b03f5f7f11d50a3a" %>
<%@ Import Namespace="System" %>
<%@ Import Namespace="System.Configuration" %>
<%@ Import Namespace="System.Data" %>
<%@ Import Namespace="System.Data.SqlClient" %>
<%@ Import Namespace="System.Linq" %>
<%@ Import Namespace="System.Security.Cryptography" %>
<%@ Import Namespace="System.Text" %>
<%@ Import Namespace="SesUtilities" %>
<script runat="server">
  static readonly byte[] AdditionalEntropy = { 23, 17, 41, 57, 71 };
  const int SaltSize = 10;

  string FixedQ = "";
  string UserQ = "";
  string StatusHtml = "";
  string Passed = "F";
  string MicsIdValue = "";
  bool ShowForm = true;

  protected void Page_Load(object sender, EventArgs e)
  {
    if (!MicsDbAuth.IsEnabled())
    {
      StatusHtml = "<span style=\"color:red;font-style:italic\">Password recovery requires database authentication (UseDbAuth).</span>";
      ShowForm = false;
      Passed = "N";
      return;
    }

    string id = (Request.QueryString["id"] ?? Request.Form["micsId"] ?? "").Trim();
    MicsIdValue = Server.HtmlEncode(id);
    if (string.IsNullOrEmpty(id))
    {
      StatusHtml = "<span style=\"color:red;font-style:italic\">Enter a Mics ID on the login page, then choose Forgot your password?</span>";
      ShowForm = false;
      Passed = "N";
      return;
    }

    Session["plogin"] = id;

    if (string.Equals(Request.HttpMethod, "POST", StringComparison.OrdinalIgnoreCase)
        && string.Equals(Request.Form["action"], "submit", StringComparison.OrdinalIgnoreCase))
    {
      ProcessSubmit(id);
      return;
    }

    LoadQuestions(id);
  }

  void LoadQuestions(string id)
  {
    try
    {
      if (MicsDbAuth.GetPrimarySchema(id) == null)
      {
        StatusHtml = "<span style=\"color:red;font-style:italic\">Your account is not set up to use this function (1). Please contact FCSA</span>";
        ShowForm = false;
        Passed = "N";
        return;
      }

      using (SqlConnection cn = new SqlConnection(MicsDbAuth.GetSqlClientConnectionString()))
      {
        cn.Open();
        using (SqlCommand cmd = new SqlCommand("SELECT fixed_questione, user_questione FROM dbo.selectqa(@id)", cn))
        {
          cmd.Parameters.Add("@id", SqlDbType.VarChar, 32).Value = id;
          using (SqlDataReader d = cmd.ExecuteReader())
          {
            if (!d.Read())
            {
              StatusHtml = "<span style=\"color:red;font-style:italic\">Your account is not set up to use this function. Please contact FCSA (or use Set Up Password Recovery after login).</span>";
              ShowForm = false;
              Passed = "N";
              return;
            }
            byte[] fq = (byte[])d["fixed_questione"];
            byte[] uq = (byte[])d["user_questione"];
            FixedQ = Server.HtmlEncode(GetString(ProtectedData.Unprotect(fq, AdditionalEntropy, DataProtectionScope.LocalMachine)).TrimEnd((char)0));
            UserQ = Server.HtmlEncode(GetString(ProtectedData.Unprotect(uq, AdditionalEntropy, DataProtectionScope.LocalMachine)).TrimEnd((char)0));
          }
        }
      }
    }
    catch (Exception ex)
    {
      StatusHtml = "<span style=\"color:red;font-style:italic\">Unable to load recovery questions: " + Server.HtmlEncode(ex.Message) + "</span>";
      ShowForm = false;
      Passed = "N";
    }
  }

  void ProcessSubmit(string id)
  {
    string fixedA = (Request.Form["fixedA"] ?? "").Trim();
    string userA = (Request.Form["userA"] ?? "").Trim();
    LoadQuestions(id);
    if (Passed == "N" || !ShowForm)
      return;

    if (string.IsNullOrEmpty(fixedA) || string.IsNullOrEmpty(userA))
    {
      StatusHtml = "<span style=\"color:red;font-style:italic\">You must enter both answers</span>";
      return;
    }

    try
    {
      using (SqlConnection cn = new SqlConnection(MicsDbAuth.GetSqlClientConnectionString()))
      {
        cn.Open();
        using (SqlCommand cmd = new SqlCommand("SELECT fixed_answere, user_answere, salt FROM dbo.selectqa(@id)", cn))
        {
          cmd.Parameters.Add("@id", SqlDbType.VarChar, 32).Value = id;
          using (SqlDataReader d = cmd.ExecuteReader())
          {
            if (!d.Read())
            {
              StatusHtml = "<span style=\"color:red;font-style:italic\">Your account is not set up to use this function. Please contact FCSA</span>";
              ShowForm = false;
              Passed = "N";
              return;
            }
            byte[] rFA = (byte[])d["fixed_answere"];
            byte[] rUA = (byte[])d["user_answere"];
            byte[] sqlsalt = (byte[])d["salt"];
            byte[] rsalt = new byte[SaltSize];
            System.Buffer.BlockCopy(sqlsalt, 0, rsalt, 0, SaltSize);

            if (!AnswersMatch(fixedA, rsalt, rFA) || !AnswersMatch(userA, rsalt, rUA))
            {
              StatusHtml = "<span style=\"color:red;font-style:italic\">Answers not correct</span>";
              Passed = "F";
              return;
            }
          }
        }
      }

      string newPwd = GeneratePassword();
      if (!MicsDbAuth.SetPassword(id, newPwd))
      {
        StatusHtml = "<span style=\"color:red;font-style:italic\">Failed to update password. Please contact FCSA</span>";
        return;
      }

      string userEmail = LookupUserEmail(id);
      if (string.IsNullOrWhiteSpace(userEmail))
      {
        StatusHtml = "<span style=\"color:red;font-style:italic\">You do not have an e-mail address set up in the Mics database. Please contact FCSA to have one added.</span>";
        Passed = "F";
        ShowForm = false;
        return;
      }

      bool userQueued = SesUtils.InsertEmailQueue("mics@fcsa.ca", userEmail, null,
        "New MICS password",
        "The new password generated for user " + id + " is: " + newPwd,
        null);
      bool fcsaQueued = SesUtils.send_email_sql(null, null, null,
        "New MICS password",
        "A new password was generated for user " + id,
        null, 1, false);

      Passed = "T";
      ShowForm = false;
      if (userQueued && fcsaQueued)
      {
        StatusHtml = "<span style=\"color:maroon;font-weight:bold\">Password reset successful.</span><br/>"
          + "<span class=\"o\">Your new password has been forwarded in an email.</span><br/>"
          + "<span class=\"b\">Close this window and log in with your new password.</span>";
      }
      else
      {
        StatusHtml = "<span style=\"color:red;font-style:italic\">Password was updated but email delivery failed. Please contact FCSA.</span><br/>"
          + "<span class=\"o\">Your new password is:</span> <code>" + Server.HtmlEncode(newPwd) + "</code>";
      }
    }
    catch (Exception ex)
    {
      StatusHtml = "<span style=\"color:red;font-style:italic\">" + Server.HtmlEncode(ex.Message) + "</span>";
    }
  }

  static string LookupUserEmail(string id)
  {
    using (SqlConnection cn = new SqlConnection(MicsDbAuth.GetSqlClientConnectionString()))
    {
      cn.Open();
      using (SqlCommand cmd = new SqlCommand("select email from dbo.selectemail(@id)", cn))
      {
        cmd.Parameters.Add("@id", SqlDbType.VarChar, 32).Value = id;
        object result = cmd.ExecuteScalar();
        return result == null || result == DBNull.Value ? "" : result.ToString().Trim();
      }
    }
  }

  static bool AnswersMatch(string answer, byte[] salt, byte[] expected)
  {
    int size = answer.Length * 2;
    byte[] raw = GetBytes(answer);
    byte[] trimmed = new byte[size];
    System.Buffer.BlockCopy(raw, 0, trimmed, 0, size);
    byte[] salted = new byte[salt.Length + trimmed.Length];
    System.Buffer.BlockCopy(salt, 0, salted, 0, salt.Length);
    System.Buffer.BlockCopy(trimmed, 0, salted, salt.Length, trimmed.Length);
    using (var sha = new SHA256Managed())
    {
      return sha.ComputeHash(salted).SequenceEqual(expected);
    }
  }

  static byte[] GetBytes(string instr)
  {
    byte[] bytes = new byte[500];
    System.Buffer.BlockCopy(instr.ToCharArray(), 0, bytes, 0, instr.Length * 2);
    return bytes;
  }

  static string GetString(byte[] bytes)
  {
    char[] chars = new char[bytes.Length / 2];
    System.Buffer.BlockCopy(bytes, 0, chars, 0, bytes.Length);
    return new string(chars);
  }

  static string GeneratePassword()
  {
    const string L = "abcdefgijkmnopqrstwxyz";
    const string U = "ABCDEFGHJKLMNPQRSTWXYZ";
    const string N = "23456789";
    const string S = "*$-+?_&=!%";
    var rng = RandomNumberGenerator.Create();
    char[] pwd = new char[10];
    pwd[0] = Pick(rng, L);
    pwd[1] = Pick(rng, U);
    pwd[2] = Pick(rng, N);
    pwd[3] = Pick(rng, S);
    string all = L + U + N + S;
    for (int i = 4; i < pwd.Length; i++)
      pwd[i] = Pick(rng, all);
    // shuffle
    for (int i = pwd.Length - 1; i > 0; i--)
    {
      int j = NextInt(rng, i + 1);
      char t = pwd[i]; pwd[i] = pwd[j]; pwd[j] = t;
    }
    return new string(pwd);
  }

  static char Pick(RandomNumberGenerator rng, string alphabet)
  {
    return alphabet[NextInt(rng, alphabet.Length)];
  }

  static int NextInt(RandomNumberGenerator rng, int maxExclusive)
  {
    byte[] b = new byte[4];
    rng.GetBytes(b);
    return (int)(BitConverter.ToUInt32(b, 0) % (uint)maxExclusive);
  }
</script>
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>Password Recovery</title>
  <link href="../styleSheets/main.css" type="text/css" rel="stylesheet">
  <link href="../styleSheets/login.css" type="text/css" rel="stylesheet">
</head>
<body>
  <form method="post" action="pwd-reset.aspx?id=<%= MicsIdValue %>">
    <input type="hidden" name="action" value="submit">
    <input type="hidden" name="micsId" value="<%= MicsIdValue %>">
    <br>
<% if (ShowForm) { %>
    <table align="center">
      <tr>
        <td align="center" colspan="3" class="o">Enter your answers to the two questions</td>
      </tr>
      <tr>
        <td><input readonly disabled size="40" value="<%= FixedQ %>"></td>
        <td class="o">Answer</td>
        <td><input name="fixedA" size="40" maxlength="32" autocomplete="off"></td>
      </tr>
      <tr><td colspan="3">&nbsp;</td></tr>
      <tr>
        <td><input readonly disabled size="40" value="<%= UserQ %>"></td>
        <td class="o">Answer</td>
        <td><input name="userA" size="40" maxlength="32" autocomplete="off"></td>
      </tr>
    </table>
    <br>
    <table align="center">
      <tr>
        <td><input class="bt" type="submit" value="Submit" <%= Passed == "T" || Passed == "N" ? "disabled" : "" %>></td>
        <td><input class="bt" type="reset" value="Reset"></td>
        <td><input class="bt" type="button" value="Close" onclick="window.close()"></td>
      </tr>
    </table>
<% } else { %>
    <table align="center">
      <tr><td align="center"><input class="bt" type="button" value="Close" onclick="window.close()"></td></tr>
    </table>
<% } %>
    <br>
    <div align="center"><%= StatusHtml %></div>
  </form>
</body>
</html>
