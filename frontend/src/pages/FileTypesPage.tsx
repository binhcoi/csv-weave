import { Badge, Button, Group, Stack, Text, Title } from '@mantine/core'
import { useDocumentTitle } from '@mantine/hooks'
import { IconPlus } from '@tabler/icons-react'
import Collection, { type CollectionField } from '../components/Collection'
import PreviewNote from '../components/PreviewNote'

interface ExampleFileType {
  name: string
  description: string
  columns: number
  rules: number
}

const exampleFileTypes: ExampleFileType[] = [
  {
    name: 'Customer import',
    description: 'Raw customer rows as exported by the legacy system',
    columns: 8,
    rules: 14,
  },
  {
    name: 'CRM contacts',
    description: 'Contact format accepted by the CRM bulk importer',
    columns: 6,
    rules: 9,
  },
  {
    name: 'Order lines',
    description: 'One row per ordered item, with totals in cents',
    columns: 11,
    rules: 21,
  },
]

const fields: CollectionField<ExampleFileType>[] = [
  { key: 'name', label: 'Name', render: (fileType) => fileType.name },
  { key: 'description', label: 'Description', render: (fileType) => fileType.description },
  {
    key: 'columns',
    label: 'Columns',
    render: (fileType) => <Badge variant="light">{fileType.columns}</Badge>,
  },
  {
    key: 'rules',
    label: 'Validation rules',
    render: (fileType) => (
      <Badge variant="light" color="gray">
        {fileType.rules}
      </Badge>
    ),
  },
]

function FileTypesPage() {
  useDocumentTitle('File types · CSVWeave')

  return (
    <Stack gap="lg">
      <Group justify="space-between" align="center">
        <Title order={1}>File types</Title>
        <Button leftSection={<IconPlus size={16} />} disabled>
          New file type
        </Button>
      </Group>
      <Text c="dimmed" maw="42rem">
        A file type is a reusable CSV format: its ordered columns and the validation rules on each
        column. Validation runs check a file against its type; transformation maps convert between
        two types.
      </Text>
      <PreviewNote>
        Example data to settle the look and feel. Creating and editing file types arrives with the
        editor milestone.
      </PreviewNote>
      <Collection items={exampleFileTypes} fields={fields} itemKey={(fileType) => fileType.name} />
    </Stack>
  )
}

export default FileTypesPage
