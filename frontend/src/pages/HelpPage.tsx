import { Anchor, Code, List, Stack, Table, Text, Title } from '@mantine/core'
import { useDocumentTitle } from '@mantine/hooks'
import { Link } from 'react-router'

const concepts = [
  ['File type', 'A reusable CSV format: ordered columns, each with validation rules.'],
  ['Column', 'One position in a file type, identified by header name, with its own rules.'],
  [
    'Catalog entry',
    'An available validator or transformer, with a schema describing its settings.',
  ],
  ['Rule', 'A catalog entry applied to a column or a map, with concrete settings.'],
  [
    'Transformation map',
    'Converts one file type into another; each transformation fills a destination column.',
  ],
  ['Data file', 'An uploaded CSV associated with a file type.'],
  ['Validation run', 'A background check of a data file against its file type.'],
  ['Conversion run', 'A background conversion of a data file using a transformation map.'],
]

function HelpPage() {
  useDocumentTitle('Help · CSVWeave')

  return (
    <Stack gap="lg" maw="48rem">
      <Title order={1}>Help</Title>
      <Text>
        CSVWeave defines CSV formats, validates files against them, and converts files between
        formats. Configure formats and maps once, then run them against uploaded files as often as
        needed.
      </Text>

      <Title order={2}>Concepts</Title>
      <Table withTableBorder>
        <Table.Tbody>
          {concepts.map(([term, meaning]) => (
            <Table.Tr key={term}>
              <Table.Td fw={600} w="12rem">
                {term}
              </Table.Td>
              <Table.Td>{meaning}</Table.Td>
            </Table.Tr>
          ))}
        </Table.Tbody>
      </Table>

      <Title order={2}>Typical workflow</Title>
      <List type="ordered" spacing="sm">
        <List.Item>
          Under{' '}
          <Anchor component={Link} to="/file-types">
            File types
          </Anchor>
          , describe the CSV you receive: its columns, in order, and the validations each column
          must pass — required, length, regex, numeric, date, or same-row comparisons.
        </List.Item>
        <List.Item>
          Create a second file type for the format you need to produce, then connect the two under{' '}
          <Anchor component={Link} to="/maps">
            Transformation maps
          </Anchor>
          : each destination column gets a transformation (copy, parse, concatenate, arithmetic,
          formatting, and so on) fed by one or more source columns. Destination columns may stay
          unmapped.
        </List.Item>
        <List.Item>
          Under{' '}
          <Anchor component={Link} to="/files">
            Files and runs
          </Anchor>
          , upload a CSV for a file type. Start a validation to check it against its type, or a
          conversion with a compatible map to produce the target format.
        </List.Item>
        <List.Item>
          Follow the run&apos;s progress and accepted/rejected counts, then download the converted
          file or the rejection report.
        </List.Item>
      </List>

      <Title order={2}>Runs and rejection reports</Title>
      <Text>
        Validation and conversion execute in the background, so large files never block the browser.
        A run moves from pending to running to completed or failed, and shows how many rows were
        accepted and rejected. Starting the same operation again for an unchanged file and
        configuration reuses the existing run instead of repeating the work.
      </Text>
      <Text>
        A rejected row never stops a run: valid rows continue through conversion, while rejected
        rows are omitted from the output and written to the rejection report. Each report line
        records the row (<Code>record</Code>), the <Code>stage</Code> where it failed, the{' '}
        <Code>column</Code> and <Code>operation</Code> involved, and the <Code>reason</Code>, so the
        source data can be corrected and re-uploaded.
      </Text>
    </Stack>
  )
}

export default HelpPage
