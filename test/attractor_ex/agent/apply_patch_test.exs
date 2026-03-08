defmodule AttractorEx.Agent.ApplyPatchTest do
  use ExUnit.Case, async: true

  alias AttractorEx.Agent.{ApplyPatch, LocalExecutionEnvironment}

  test "apply_patch adds, updates, moves, and deletes files" do
    root = tmp_dir()
    env = LocalExecutionEnvironment.new(working_dir: root)
    File.write!(Path.join(root, "sample.txt"), "alpha\nbeta\n")

    add_patch = """
    *** Begin Patch
    *** Add File: nested/new.txt
    +first
    +second
    *** End Patch
    """

    assert {:ok, [%{operation: "add", path: "nested/new.txt"}]} = ApplyPatch.apply(env, add_patch)
    assert File.read!(Path.join(root, "nested/new.txt")) == "first\nsecond"

    update_patch = """
    *** Begin Patch
    *** Update File: sample.txt
    @@
    -alpha
    +gamma
    *** End Patch
    """

    assert {:ok, [%{operation: "update", path: "sample.txt"}]} =
             ApplyPatch.apply(env, update_patch)

    assert File.read!(Path.join(root, "sample.txt")) == "gamma\nbeta\n"

    move_patch = """
    *** Begin Patch
    *** Update File: sample.txt
    *** Move to: moved.txt
    @@
     gamma
    -beta
    +delta
    *** End Patch
    """

    assert {:ok, [%{operation: "update+move", path: "moved.txt"}]} =
             ApplyPatch.apply(env, move_patch)

    refute File.exists?(Path.join(root, "sample.txt"))
    assert File.read!(Path.join(root, "moved.txt")) == "gamma\ndelta\n"

    delete_patch = """
    *** Begin Patch
    *** Delete File: moved.txt
    *** End Patch
    """

    assert {:ok, [%{operation: "delete", path: "moved.txt"}]} =
             ApplyPatch.apply(env, delete_patch)

    refute File.exists?(Path.join(root, "moved.txt"))
  end

  test "apply_patch rejects invalid environments and malformed envelopes" do
    assert {:error, "apply_patch requires LocalExecutionEnvironment"} =
             ApplyPatch.apply(%AttractorExTest.ExecutionEnv{}, "*** Begin Patch\n*** End Patch")

    assert {:error, "patch must start with *** Begin Patch"} =
             ApplyPatch.apply(
               LocalExecutionEnvironment.new(),
               "*** Update File: x\n*** End Patch"
             )

    assert {:error, "patch must end with *** End Patch"} =
             ApplyPatch.apply(LocalExecutionEnvironment.new(), "*** Begin Patch\n*** Add File: x")
  end

  test "apply_patch surfaces parser and verification failures" do
    root = tmp_dir()
    env = LocalExecutionEnvironment.new(working_dir: root)
    File.write!(Path.join(root, "sample.txt"), "alpha\n")

    invalid_add = """
    *** Begin Patch
    *** Add File: sample.txt
    sample
    *** End Patch
    """

    assert {:error, message} = ApplyPatch.apply(env, invalid_add)
    assert message =~ "invalid add line"

    mismatch = """
    *** Begin Patch
    *** Update File: sample.txt
    @@
    -beta
    +gamma
    *** End Patch
    """

    assert {:error, message} = ApplyPatch.apply(env, mismatch)
    assert message =~ "failed to locate patch anchor"

    invalid_update = """
    *** Begin Patch
    *** Update File: sample.txt
    nope
    *** End Patch
    """

    assert {:error, message} = ApplyPatch.apply(env, invalid_update)
    assert message =~ "invalid update hunk line"
  end

  test "apply_patch reports delete failures" do
    env = LocalExecutionEnvironment.new(working_dir: tmp_dir())

    delete_patch = """
    *** Begin Patch
    *** Delete File: missing.txt
    *** End Patch
    """

    assert {:error, message} = ApplyPatch.apply(env, delete_patch)
    assert message =~ "failed to delete missing.txt"
  end

  test "apply_patch reports structural operation errors" do
    root = tmp_dir()
    env = LocalExecutionEnvironment.new(working_dir: root)
    File.write!(Path.join(root, "sample.txt"), "alpha\nbeta")

    empty_add = """
    *** Begin Patch
    *** Add File: sample.txt
    *** End Patch
    """

    assert {:error, message} = ApplyPatch.apply(env, empty_add)
    assert message =~ "add file operation requires at least one + line"

    missing_hunks = """
    *** Begin Patch
    *** Update File: sample.txt
    *** End Patch
    """

    assert {:error, message} = ApplyPatch.apply(env, missing_hunks)
    assert message =~ "update file operation requires hunks"

    unrecognized = """
    *** Begin Patch
    ????
    *** End Patch
    """

    assert {:error, message} = ApplyPatch.apply(env, unrecognized)
    assert message =~ "unrecognized patch line"
  end

  test "apply_patch reports read and hunk-consumption failures" do
    root = tmp_dir()
    env = LocalExecutionEnvironment.new(working_dir: root)
    File.write!(Path.join(root, "sample.txt"), "alpha\nbeta")

    missing_file = """
    *** Begin Patch
    *** Update File: missing.txt
    @@
    -alpha
    +gamma
    *** End Patch
    """

    assert {:error, message} = ApplyPatch.apply(env, missing_file)
    assert message =~ "failed to read missing.txt"

    context_mismatch = """
    *** Begin Patch
    *** Update File: sample.txt
    @@
     alpha
     gamma
    *** End Patch
    """

    assert {:error, message} = ApplyPatch.apply(env, context_mismatch)
    assert message =~ "context mismatch"

    delete_mismatch = """
    *** Begin Patch
    *** Update File: sample.txt
    @@
     alpha
    -gamma
    *** End Patch
    """

    assert {:error, message} = ApplyPatch.apply(env, delete_mismatch)
    assert message =~ "delete mismatch"

    invalid_hunk_line = """
    *** Begin Patch
    *** Update File: sample.txt
    @@
    !oops
    *** End Patch
    """

    assert {:error, message} = ApplyPatch.apply(env, invalid_hunk_line)
    assert message =~ "invalid patch operation line"
  end

  defp tmp_dir do
    root =
      Path.join(System.tmp_dir!(), "attractor-apply-patch-#{System.unique_integer([:positive])}")

    File.mkdir_p!(root)
    root
  end
end
