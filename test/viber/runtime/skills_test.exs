defmodule Viber.Runtime.SkillsTest do
  use ExUnit.Case, async: true

  alias Viber.Runtime.Skills

  @moduletag :tmp_dir

  defp write_skill(tmp_dir, dir_name, content, extra_files \\ []) do
    skill_dir = Path.join([tmp_dir, ".viber", "skills", dir_name])
    File.mkdir_p!(skill_dir)
    File.write!(Path.join(skill_dir, "SKILL.md"), content)

    Enum.each(extra_files, fn {name, body} ->
      path = Path.join(skill_dir, name)
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, body)
    end)
  end

  describe "discover/1" do
    test "returns empty list when no skills directory exists", %{tmp_dir: tmp_dir} do
      assert Skills.discover(tmp_dir) == []
    end

    test "parses frontmatter name and description", %{tmp_dir: tmp_dir} do
      write_skill(tmp_dir, "release-check", """
      ---
      name: release-check
      description: Verify a release build before shipping
      ---

      Full instructions here.
      """)

      assert [skill] = Skills.discover(tmp_dir)
      assert skill.name == "release-check"
      assert skill.description == "Verify a release build before shipping"
      assert String.ends_with?(skill.path, "SKILL.md")
    end

    test "falls back to directory name and first body line", %{tmp_dir: tmp_dir} do
      write_skill(tmp_dir, "db-audit", """
      # Audit database queries

      Steps follow.
      """)

      assert [skill] = Skills.discover(tmp_dir)
      assert skill.name == "db-audit"
      assert skill.description == "Audit database queries"
    end

    test "sorts skills by name", %{tmp_dir: tmp_dir} do
      write_skill(tmp_dir, "zeta", "---\nname: zeta\ndescription: z\n---\nbody")
      write_skill(tmp_dir, "alpha", "---\nname: alpha\ndescription: a\n---\nbody")

      assert ["alpha", "zeta"] = Skills.discover(tmp_dir) |> Enum.map(& &1.name)
    end
  end

  describe "load/2" do
    test "returns full body and bundled files", %{tmp_dir: tmp_dir} do
      write_skill(
        tmp_dir,
        "review",
        """
        ---
        name: review
        description: Review changes
        ---

        Read the diff, then judge it.
        """,
        [{"checklist.md", "- correctness"}, {"refs/style.md", "- style"}]
      )

      assert {:ok, skill} = Skills.load(tmp_dir, "review")
      assert skill.name == "review"
      assert skill.content == "Read the diff, then judge it."
      assert skill.files == ["checklist.md", "refs/style.md"]
    end

    test "returns error for unknown skill naming available ones", %{tmp_dir: tmp_dir} do
      write_skill(tmp_dir, "review", "---\nname: review\ndescription: r\n---\nbody")

      assert {:error, message} = Skills.load(tmp_dir, "nope")
      assert message =~ "Unknown skill 'nope'"
      assert message =~ "review"
    end

    test "returns error when no skills installed", %{tmp_dir: tmp_dir} do
      assert {:error, message} = Skills.load(tmp_dir, "anything")
      assert message =~ "no skills are installed"
    end
  end
end
