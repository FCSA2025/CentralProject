<%@ Page Language="C#" AutoEventWireup="true" CodeBehind="index.aspx.cs" Inherits="mics.RemIcsReWrite_index" %>
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>CloudMics 2022 — TS Files</title>
  <style>
    body { font-family: Segoe UI, Arial, sans-serif; margin: 2rem; background: #f4f6fb; color: #1a1a2e; }
    h1 { color: #0c1566; }
    .meta, .diag { background: #fff; border: 1px solid #dde2ef; border-radius: 8px; padding: 1rem; margin: 1rem 0; }
    .diag { font-size: 0.9rem; }
    .diag dt { font-weight: 600; margin-top: 0.35rem; }
    .diag dd { margin: 0.1rem 0 0 0; font-family: Consolas, monospace; }
    ul.files { list-style: none; padding: 0; }
    ul.files li { margin: 0.35rem 0; }
    ul.files a { color: #121f91; font-weight: 600; text-decoration: none; }
    ul.files a:hover { text-decoration: underline; }
    .toolbar a { margin-right: 1rem; color: #121f91; }
    .empty { color: #667; font-style: italic; }
    .error { color: #b71c1c; }
  </style>
</head>
<body>
  <h1>CloudMics 2022 — TS Files</h1>
  <div class="toolbar">
    <a href="shell.aspx">Shell</a>
    <a href="file.aspx?name=cmxts01">Open cmxts01</a>
    <a href="logoff.ashx">Log off</a>
    <a href="/admin/">FCSA Testing</a>
  </div>
  <%= MetaHtml %>
  <%= DiagHtml %>
  <h2>TS tables</h2>
  <%= FilesHtml %>
</body>
</html>
