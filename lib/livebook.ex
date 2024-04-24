defmodule Livebook do
  @moduledoc """
  I generate out extra information for Livebook

  My main purpose is to generate out the TOC for each livebook
  document we have.

  to do this please run `toc_toplevel/0`

  ## API

  - `toc_toplevel/0`
  - `get_all_livemd_documents/0`
  - `example_toc/0`

  """

  ####################################################################
  ##                            Auto Run                             #
  ####################################################################

  @doc """
  I get out all live view docs
  """
  @spec get_all_livemd_documents() :: list(Path.t())
  def get_all_livemd_documents() do
    get_livemd_documents("./documentation")
  end

  @doc """
  I provide an example of what a TOC looks like
  """
  @spec example_toc() :: :ok
  def example_toc() do
    Livebook.get_all_livemd_documents()
    |> Enum.map(fn x -> String.replace_prefix(x, "documentation/", "") end)
    |> generate_TOC()
    |> IO.puts()
  end

  @doc """
  I generate out the TOC for all liveview docs
  """
  def toc_toplevel() do
    paths = Livebook.get_all_livemd_documents()

    paths_without_doc =
      paths
      |> Enum.map(fn x -> String.replace_prefix(x, "documentation/", "") end)

    paths
    |> Enum.map(fn p ->
      {p,
       generate_TOC(
         paths_without_doc,
         count_depth(String.replace_prefix(p, "documentation/", ""))
       )}
    end)
    |> Enum.each(fn {path, toc} ->
      inject_TOC(toc, path)
    end)
  end

  ####################################################################
  ##                            Injection                            #
  ####################################################################

  @spec inject_TOC(String.t(), Path.t()) :: :ok
  def inject_TOC(toc, path) do
    data =
      File.read!(path)
      |> Livebook.change_header("##", "Index", toc)

    File.write!(path, data)
  end

  ####################################################################
  ##                        Getting Documents                        #
  ####################################################################

  @doc """
  Gets all livemd documents in a sorted list given a path.
  """
  @spec get_livemd_documents(Path.t()) :: list(Path.t())
  def get_livemd_documents(dir) do
    [dir | dir_from_path(dir)]
    |> Stream.map(fn x -> Path.wildcard(Path.join(x, "*livemd")) end)
    |> Stream.concat()
    |> Enum.sort()
  end

  ####################################################################
  ##                            Generation                           #
  ####################################################################

  @doc """
  Generates out a TOC, given a series of nested documents

  We take a path, and a place where we should be calculating the TOC from.

  ## Example

  """
  @spec generate_TOC(list(Path.t()), non_neg_integer()) :: String.t()
  @spec generate_TOC(list(Path.t())) :: String.t()
  def generate_TOC(documents, from_depth \\ 0) do
    documents
    |> Livebook.add_heading_num()
    |> Enum.map(fn {f, d, n} -> generate_heading(f, d, n, from_depth) end)
    |> Enum.join("\n")
  end

  @spec add_heading_num(list(String.t())) ::
          list({String.t(), non_neg_integer(), non_neg_integer()})
  def add_heading_num(documents) do
    documents
    |> Stream.map(fn x -> {x, count_depth(x)} end)
    # FOLDS ARE BAD
    # We simply have a stack for checking to resume numbering after
    # going to a sister after nesting
    |> Enum.reduce({[], 0, 0, []}, fn {file, depth_f},
                                      {list, depth_prev, last, stack} ->
      up_n = depth_prev - depth_f
      # If the previous depth agrees, increment the numbers
      cond do
        # The previous filing was our sister
        depth_f == depth_prev ->
          {[{file, depth_f, last + 1} | list], depth_f, last + 1, stack}

        # The previous file is a parent
        depth_f > depth_prev ->
          {[{file, depth_f, 1} | list], depth_f, 1, [last | stack]}

        # The previous file is a sister of one of our ancestors
        depth_f < depth_prev ->
          {[{file, depth_f, hd(stack) + 1} | list], depth_f,
           Enum.at(stack, up_n - 1) + 1, Enum.drop(stack, up_n)}
      end
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  @spec generate_heading(String.t(), non_neg_integer(), non_neg_integer()) ::
          String.t()
  @spec generate_heading(
          String.t(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer()
        ) :: String.t()
  def generate_heading(path, depth, numbering, from_depth \\ 1) do
    String.duplicate(" ", 3 * depth) <>
      to_string(numbering) <>
      ". " <>
      "[#{name(path)}](#{relative(path, from_depth)})"
  end

  @spec dir_from_path(String.t()) :: list(String.t())
  def dir_from_path(dir) do
    File.ls!(dir)
    |> Stream.map(&Path.join(dir, &1))
    |> Stream.filter(&File.dir?(&1))
    |> Enum.map(fn x -> [x | dir_from_path(x)] end)
    |> Enum.concat()
  end

  ####################################################################
  ##                           Name Help                             #
  ####################################################################
  @spec name(String.t()) :: String.t()
  defp name(path) do
    Path.basename(path, ".livemd")
    |> String.split("-")
    |> Stream.map(&String.capitalize(&1))
    |> Enum.join(" ")
  end

  @spec relative(Path.t(), non_neg_integer) :: Path.t()
  defp relative(path, relative) do
    "./" <>
      String.duplicate("../", relative) <>
      path
  end

  @spec count_depth(Path.t()) :: non_neg_integer()
  def count_depth(path) do
    path
    |> String.graphemes()
    |> Enum.count(&(&1 == "/"))
  end

  @doc """
  I replace the header with the given TOC

  ### Example
    > markdown_text = "## Intro ... \n## Index \n text here \n ## Conclusion \n All good"
    > Livebook.change_header(markdown_text, "##", "Index", "New Content") |> IO.puts
       ## Intro ...
       ## Index
       New Content
       ## Conclusion
       All good
      :ok
  """
  def change_header(markdown, header_level, start_header, new_text) do
    header_regex =
      ~r/^#{header_level}\s+#{start_header}\s*$(.*?)(?=\n#{header_level}\s+|##|\z)/ms

    updated_markdown =
      String.replace(
        markdown,
        header_regex,
        "#{header_level} #{start_header}\n#{new_text}\n"
      )

    updated_markdown
  end
end