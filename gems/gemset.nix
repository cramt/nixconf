{
  language_server-protocol = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "0gvb1j8xsqxms9mww01rmdl78zkd72zgxaap56bhv8j45z05hp1x";
      type = "gem";
    };
    version = "3.17.0.3";
  };
  logger = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "0lwncq2rf8gm79g2rcnnyzs26ma1f4wnfjm6gs4zf2wlsdz5in9s";
      type = "gem";
    };
    version = "1.6.1";
  };
  prism = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "0w6v6hc7pk7hrsvkpr1jkk55syna94im7yzmjim0lly2aadwn86c";
      type = "gem";
    };
    version = "1.0.0";
  };
  rbs = {
    dependencies = ["logger"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "0lph27fb8n2bwnqaqy0xm1jwjar7ljqrcq16ajhylh0yvfhfwqpj";
      type = "gem";
    };
    version = "3.5.3";
  };
  ruby-lsp = {
    dependencies = ["language_server-protocol" "prism" "rbs" "sorbet-runtime"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "12vrkd5650m7rfh23lzhmp6384y29adxlhmsq5ll6d7ysc6v8iv1";
      type = "gem";
    };
    version = "0.17.17";
  };
  sorbet-runtime = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "0j8wq78778p9wrx1lwb23zd1f6cyh2v8aidzf5w0sw91dgy4jmg3";
      type = "gem";
    };
    version = "0.5.11566";
  };
}
